#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s <file.plasmoid>\n' "$0" >&2
    exit 2
fi

FILE=$1
[ -f "$FILE" ] || { printf 'ERROR: missing file: %s\n' "$FILE" >&2; exit 1; }

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

unzip -tqq "$FILE"
unzip -qq "$FILE" -d "$TMP/pkg"

for req in metadata.json LICENSE README.md contents/ui/main.qml contents/config/main.xml contents/code/app-memoryctl.py contents/code/app-memory-daemon.py; do
    [ -e "$TMP/pkg/$req" ] || { printf 'ERROR: package missing %s\n' "$req" >&2; exit 1; }
done

python3 - "$ROOT/metadata.json" "$TMP/pkg/metadata.json" "$(basename "$FILE")" <<'PY'
import json, pathlib, re, sys
src = json.load(open(sys.argv[1], encoding="utf-8"))
pkg = json.load(open(sys.argv[2], encoding="utf-8"))
name = sys.argv[3]
for key in ("Id", "Version", "License", "Name"):
    a = src["KPlugin"].get(key)
    b = pkg["KPlugin"].get(key)
    if a != b:
        raise SystemExit(f"metadata mismatch for {key}: source={a!r} package={b!r}")
if pkg["KPlugin"].get("Id") != "cz.pitriss.appmemorybar":
    raise SystemExit("unexpected plugin Id")
if pkg["KPlugin"].get("License") != "MIT":
    raise SystemExit("unexpected license")
ver = pkg["KPlugin"]["Version"]
expected = f"app-memory-bar-{ver}.plasmoid"
if name != expected:
    raise SystemExit(f"filename mismatch: expected {expected}, got {name}")
PY

if find "$TMP/pkg" -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q .; then
    printf 'ERROR: Python bytecode found in package\n' >&2
    exit 1
fi
if find "$TMP/pkg" -type d -name '__pycache__' -print -quit | grep -q .; then
    printf 'ERROR: __pycache__ found in package\n' >&2
    exit 1
fi

printf 'OK: %s\n' "$FILE"
