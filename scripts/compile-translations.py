#!/usr/bin/env python3
import ast
import re
import struct
import sys
from pathlib import Path

DOMAIN = "plasma_applet_cz.pitriss.appmemorybar"
LOCALES = ("cs", "de", "pl", "ru", "uk", "sk")


def parse_po(path):
    entries = []
    current = {}
    field = None
    fuzzy = False

    def flush():
        nonlocal current, field, fuzzy
        if current:
            current["fuzzy"] = fuzzy
            entries.append(current)
        current = {}
        field = None
        fuzzy = False

    for raw in path.read_text(encoding="utf-8").splitlines() + [""]:
        line = raw.strip()
        if not line:
            flush()
            continue
        if line.startswith("#,"):
            flags = {item.strip() for item in line[2:].split(",")}
            fuzzy = "fuzzy" in flags
            continue
        if line.startswith("#"):
            continue

        match = re.match(r'msgid_plural\s+(".*")$', line)
        if match:
            field = ("msgid_plural", None)
            current["msgid_plural"] = ast.literal_eval(match.group(1))
            continue

        match = re.match(r'msgid\s+(".*")$', line)
        if match:
            field = ("msgid", None)
            current["msgid"] = ast.literal_eval(match.group(1))
            continue

        match = re.match(r'msgstr\[(\d+)\]\s+(".*")$', line)
        if match:
            index = int(match.group(1))
            field = ("msgstr", index)
            current.setdefault("msgstr", {})[index] = ast.literal_eval(match.group(2))
            continue

        match = re.match(r'msgstr\s+(".*")$', line)
        if match:
            field = ("msgstr", 0)
            current.setdefault("msgstr", {})[0] = ast.literal_eval(match.group(1))
            continue

        if line.startswith('"') and field:
            value = ast.literal_eval(line)
            if field[0] == "msgstr":
                strings = current.setdefault("msgstr", {})
                strings[field[1]] = strings.get(field[1], "") + value
            else:
                current[field[0]] = current.get(field[0], "") + value
            continue

        raise ValueError(f"{path}: cannot parse line: {raw}")

    return entries


def entry_key(entry):
    msgid = entry.get("msgid", "")
    plural = entry.get("msgid_plural")
    return (msgid, plural)


def plural_count(entries, path):
    header = next((entry for entry in entries if entry.get("msgid") == ""), None)
    if not header:
        raise ValueError(f"{path}: missing PO header")
    header_text = header.get("msgstr", {}).get(0, "")
    match = re.search(r"Plural-Forms:\s*nplurals=(\d+);", header_text)
    if not match:
        raise ValueError(f"{path}: missing Plural-Forms header")
    return int(match.group(1))


def validate_catalogs(po_dir):
    pot_path = po_dir / "app-memory-bar.pot"
    pot_entries = parse_po(pot_path)
    expected = {
        entry_key(entry)
        for entry in pot_entries
        if entry.get("msgid", "")
    }

    for locale in LOCALES:
        path = po_dir / f"{locale}.po"
        entries = parse_po(path)
        if any(entry.get("fuzzy") for entry in entries):
            raise ValueError(f"{path}: fuzzy translations are not allowed in release catalogs")

        actual = {
            entry_key(entry)
            for entry in entries
            if entry.get("msgid", "")
        }
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        if missing or extra:
            raise ValueError(
                f"{path}: catalog mismatch; missing={missing!r}, extra={extra!r}"
            )

        nplurals = plural_count(entries, path)
        for entry in entries:
            msgid = entry.get("msgid", "")
            if not msgid:
                continue
            strings = entry.get("msgstr", {})
            if "msgid_plural" in entry:
                for index in range(nplurals):
                    if not strings.get(index, ""):
                        raise ValueError(
                            f"{path}: missing plural translation {index} for {msgid!r}"
                        )
            elif not strings.get(0, ""):
                raise ValueError(f"{path}: missing translation for {msgid!r}")


def compile_catalog(src, dst):
    entries = parse_po(src)
    messages = {}

    for entry in entries:
        if entry.get("fuzzy"):
            continue
        msgid = entry.get("msgid", "")
        strings = entry.get("msgstr", {})

        if "msgid_plural" in entry:
            key = msgid + "\0" + entry["msgid_plural"]
            count = plural_count(entries, src)
            value = "\0".join(strings[index] for index in range(count))
        else:
            key = msgid
            value = strings.get(0, "")

        messages[key] = value

    keys = sorted(messages)
    ids_blob = bytearray()
    strings_blob = bytearray()
    ids_meta = []
    strings_meta = []

    for key in keys:
        encoded = key.encode("utf-8")
        ids_meta.append((len(encoded), len(ids_blob)))
        ids_blob += encoded + b"\0"

    for key in keys:
        encoded = messages[key].encode("utf-8")
        strings_meta.append((len(encoded), len(strings_blob)))
        strings_blob += encoded + b"\0"

    count = len(keys)
    header_size = 7 * 4
    ids_table_offset = header_size
    strings_table_offset = ids_table_offset + count * 8
    ids_offset = strings_table_offset + count * 8
    strings_offset = ids_offset + len(ids_blob)

    output = bytearray(
        struct.pack(
            "<7I",
            0x950412DE,
            0,
            count,
            ids_table_offset,
            strings_table_offset,
            0,
            0,
        )
    )

    for length, offset in ids_meta:
        output += struct.pack("<2I", length, ids_offset + offset)
    for length, offset in strings_meta:
        output += struct.pack("<2I", length, strings_offset + offset)

    output += ids_blob
    output += strings_blob

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(output)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        po_dir = Path(sys.argv[2])
        validate_catalogs(po_dir)
        print("PASS: translation catalogs", file=sys.stderr)
        return 0

    if len(sys.argv) != 3:
        print(
            f"Usage: {sys.argv[0]} --check <po-dir> | <po-dir> <locale-output-dir>",
            file=sys.stderr,
        )
        return 2

    po_dir = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    validate_catalogs(po_dir)

    for locale in LOCALES:
        src = po_dir / f"{locale}.po"
        dst = out_dir / locale / "LC_MESSAGES" / f"{DOMAIN}.mo"
        compile_catalog(src, dst)

    print(f"PASS: compiled {len(LOCALES)} translation catalogs", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
