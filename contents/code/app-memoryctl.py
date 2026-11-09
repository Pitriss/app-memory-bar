#!/usr/bin/python3
from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys
import time

from app_memory_backend import (
    BACKEND_VERSION, CONFIG_PATH, STATE_PATH, app_label_for_exe, clear_budget,
    collect_units, enforce_budget, get_state_app, load_state, refresh_state,
    normalize_executable, update_registration, units_for_exact_exe, validate_limits,
)

UNIT_NAME = "app-memory-bar.service"
SYSTEM_UNIT_PATHS = (
    pathlib.Path("/usr/lib/systemd/user") / UNIT_NAME,
    pathlib.Path("/lib/systemd/user") / UNIT_NAME,
)


def unit_path() -> pathlib.Path:
    home = pathlib.Path.home()
    base = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "systemd/user"
    return base / UNIT_NAME


def daemon_path() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().with_name("app-memory-daemon.py")


def packaged_unit_path() -> pathlib.Path | None:
    for path in SYSTEM_UNIT_PATHS:
        if path.is_file():
            return path
    return None


def systemd_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'


def desired_unit() -> str:
    return "\n".join([
        "[Unit]",
        "Description=App Memory Bar backend",
        "",
        "[Service]",
        "Type=simple",
        f"ExecStart=/usr/bin/python3 -B {systemd_quote(str(daemon_path()))}",
        "Restart=on-failure",
        "RestartSec=2",
        "",
        "[Install]",
        "WantedBy=default.target",
        "",
    ])


def run_systemctl(*args: str, timeout: float = 8.0) -> subprocess.CompletedProcess:
    return subprocess.run(["systemctl", "--user", *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


def state_fresh(max_age: float = 12.0) -> bool:
    st = load_state()
    return st.get("backendVersion") == BACKEND_VERSION and (time.time() - float(st.get("generated", 0) or 0)) <= max_age


def ensure_service(wait: bool = True) -> tuple[bool, str]:
    path = unit_path()
    packaged = packaged_unit_path()
    changed = False

    if packaged is None:
        # Standalone .plasmoid installs have no packaged user unit, so keep the
        # historical self-contained behaviour and create one in XDG_CONFIG_HOME.
        path.parent.mkdir(parents=True, exist_ok=True)
        wanted = desired_unit()
        try:
            current = path.read_text() if path.exists() else ""
        except OSError:
            current = ""
        changed = current != wanted
        if changed:
            path.write_text(wanted)
            cp = run_systemctl("daemon-reload")
            if cp.returncode != 0:
                return False, (cp.stderr or cp.stdout).strip()
    elif path.exists() or path.is_symlink():
        # A per-user unit has higher precedence than /usr/lib/systemd/user. Do
        # not silently overwrite/remove user data from the widget process. The
        # packaged migration helper backs it up first.
        return False, f"per-user unit shadows packaged service: {path}; run app-memory-bar-migrate --migrate"

    state = load_state()
    version_changed = bool(state.get("backendVersion")) and state.get("backendVersion") != BACKEND_VERSION
    if not state_fresh() or changed or version_changed:
        action = "restart" if changed or version_changed else "start"
        cp = run_systemctl(action, UNIT_NAME)
        if cp.returncode != 0:
            cp = run_systemctl("enable", "--now", UNIT_NAME)
        else:
            run_systemctl("enable", UNIT_NAME)
        if cp.returncode != 0:
            return False, (cp.stderr or cp.stdout).strip()

    if wait:
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            if state_fresh(max_age=4.0):
                return True, ""
            time.sleep(0.1)
    return True, ""


def wake_service() -> None:
    try:
        run_systemctl("kill", "-s", "HUP", UNIT_NAME, timeout=3.0)
    except Exception:
        pass


def wait_generation(old_gen: float, timeout: float = 2.5) -> dict:
    deadline = time.monotonic() + timeout
    latest = load_state()
    while time.monotonic() < deadline:
        latest = load_state()
        if float(latest.get("generated", 0) or 0) > old_gen:
            return latest
        time.sleep(0.08)
    return latest


def fmt(v) -> str:
    return "max" if v == "max" else str(int(v or 0))


def output_probe(app: dict | None, display: str = "") -> None:
    if not app or not app.get("running"):
        print("STOPPED\tmax\tmax\toff")
        return
    print("\t".join([
        "RUNNING",
        str(int(app.get("current", 0) or 0)),
        fmt(app.get("high", "max")),
        fmt(app.get("max", "max")),
        str(app.get("display") or display or "App"),
        str(int(app.get("unitCount", 0) or 0)),
        ", ".join(app.get("units", []) or []),
        str(app.get("exe") or ""),
        ", ".join(app.get("processes", []) or []),
        str(app.get("enforcement") or "off"),
    ]))


def command_probe(args) -> int:
    ok, err = ensure_service(wait=True)
    if not ok:
        print(f"ERROR\tbackend\t{err}", file=sys.stderr)
        return 3
    high = int(args.high or 0)
    maximum = int(args.maximum or 0)
    maintain = str(args.enforce) == "1"
    state = load_state()
    old_gen = float(state.get("generated", 0) or 0)
    exe = normalize_executable(args.exe)
    if not exe and args.display:
        wanted = args.display.strip().lower()
        matches = [key for key, item in (state.get("scan", {}) or {}).items()
                   if str(item.get("display", "")).strip().lower() == wanted]
        if len(matches) == 1:
            exe = matches[0]
    changed = update_registration(exe, args.display, maintain, high, maximum) if exe else False
    if changed:
        wake_service()
        state = wait_generation(old_gen)
    app = get_state_app(state, exe) if exe else None
    output_probe(app, args.display)
    return 0


def command_scan(_args) -> int:
    ok, err = ensure_service(wait=True)
    if not ok:
        print(err, file=sys.stderr)
        return 3
    state = load_state()
    scan = state.get("scan", {}) if isinstance(state.get("scan"), dict) else {}
    for exe, app in sorted(scan.items(), key=lambda kv: str(kv[1].get("display", kv[0])).lower()):
        print("\t".join([
            str(app.get("display") or app_label_for_exe(exe)),
            exe,
            str(int(app.get("current", 0) or 0)),
            fmt(app.get("high", "max")),
            fmt(app.get("max", "max")),
            str(int(app.get("unitCount", 0) or 0)),
            ", ".join(app.get("units", []) or []),
            ", ".join(app.get("processes", []) or []),
        ]))
    return 0


def command_apply(args) -> int:
    high = int(args.high)
    maximum = int(args.maximum)
    valid, err = validate_limits(high, maximum)
    if not valid:
        print(f"ERROR\t{err}")
        return 2
    units = collect_units()
    target_units = units_for_exact_exe(units, args.exe)
    if not target_units:
        print("ERROR\tapplication is not running")
        return 2
    state, errors = enforce_budget(target_units, high, maximum, force=True)
    if errors:
        print("ERROR\t" + " | ".join(errors))
        return 4
    print(f"OK\t{state}\t{high}\t{maximum}")
    wake_service()
    return 0


def command_clear(args) -> int:
    units = collect_units()
    target_units = units_for_exact_exe(units, args.exe)
    if not target_units:
        print("ERROR\tapplication is not running")
        return 2
    errors = clear_budget(target_units)
    if errors:
        print("ERROR\t" + " | ".join(errors))
        return 4
    print("OK\tcleared")
    wake_service()
    return 0


def command_details(args) -> int:
    units = collect_units()
    target_units = units_for_exact_exe(units, args.exe)
    for u in sorted(target_units, key=lambda x: x.unit):
        print(f"UNIT\t{u.unit}\t{u.current}\t{fmt(u.high)}\t{fmt(u.maximum)}")
    if target_units:
        current = sum(u.current for u in target_units)
        print(f"TOTAL\t{len(target_units)}\t{current}")
    return 0


def command_ensure(_args) -> int:
    ok, err = ensure_service(wait=True)
    if not ok:
        print(f"ERROR\t{err}")
        return 3
    state = load_state()
    print(f"OK\t{UNIT_NAME}\t{state.get('backendVersion','?')}")
    return 0


def command_status(_args) -> int:
    state = load_state()
    age = time.time() - float(state.get("generated", 0) or 0)
    print(json.dumps({"backendVersion": state.get("backendVersion", ""), "age": round(age, 2), "state": str(STATE_PATH), "config": str(CONFIG_PATH)}, ensure_ascii=False))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="app-memoryctl")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ensure")
    q = sub.add_parser("scan")
    q.add_argument("nonce", nargs="?")
    sub.add_parser("status")

    q = sub.add_parser("probe-target")
    q.add_argument("exe")
    q.add_argument("legacy_prefix")
    q.add_argument("display")
    q.add_argument("enforce")
    q.add_argument("high")
    q.add_argument("maximum")

    q = sub.add_parser("apply-app")
    q.add_argument("exe")
    q.add_argument("high")
    q.add_argument("maximum")

    q = sub.add_parser("clear-app")
    q.add_argument("exe")

    q = sub.add_parser("details")
    q.add_argument("exe")

    args = p.parse_args()
    return {
        "ensure": command_ensure,
        "scan": command_scan,
        "status": command_status,
        "probe-target": command_probe,
        "apply-app": command_apply,
        "clear-app": command_clear,
        "details": command_details,
    }[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
