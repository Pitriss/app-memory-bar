#!/usr/bin/python3
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import tempfile
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from typing import Dict, Iterable, List, Optional, Set, Tuple, Union

BACKEND_VERSION = "0.10.0"
GIB = 1024 ** 3
MIB = 1024 ** 2

UID = os.getuid()
HOME = pathlib.Path.home()
XDG_CONFIG_HOME = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
XDG_RUNTIME_DIR = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{UID}"))
CONFIG_DIR = pathlib.Path(os.environ.get("APP_MEMORY_BAR_CONFIG_DIR", XDG_CONFIG_HOME / "app-memory-bar"))
CONFIG_PATH = CONFIG_DIR / "apps.json"
RUNTIME_DIR = pathlib.Path(os.environ.get("APP_MEMORY_BAR_RUNTIME_DIR", XDG_RUNTIME_DIR / "app-memory-bar"))
STATE_PATH = RUNTIME_DIR / "state.json"
PROC_ROOT = pathlib.Path(os.environ.get("APP_MEMORY_BAR_PROC_ROOT", "/proc"))
CGROUP_ROOT = pathlib.Path(os.environ.get("APP_MEMORY_BAR_CGROUP_ROOT", "/sys/fs/cgroup"))
APP_SLICE = pathlib.Path(os.environ.get(
    "APP_MEMORY_BAR_APP_SLICE",
    CGROUP_ROOT / f"user.slice/user-{UID}.slice/user@{UID}.service/app.slice",
))

HELPER_BASENAMES = {
    "sh", "bash", "dash", "zsh", "fish", "cat", "sleep", "env", "systemd-run",
    "chrome_crashpad_handler", "keepassxc-proxy", "kioworker", "plasmashell",
}


def now() -> float:
    return time.time()


def normalize_executable(exe: str) -> str:
    """Normalize /proc/PID/exe identities across in-place package upgrades.

    Linux appends the literal suffix `` (deleted)`` to /proc/PID/exe when the
    executable inode has been replaced/unlinked while the process keeps
    running.  That must not create a second logical application identity.
    """
    value = str(exe or "").strip()
    suffix = " (deleted)"
    while value.endswith(suffix):
        value = value[:-len(suffix)]
    return value


def read_text(path: pathlib.Path, default: str = "") -> str:
    try:
        return path.read_text(errors="replace").strip()
    except (OSError, PermissionError):
        return default


def read_int_or_max(path: pathlib.Path) -> Union[int, str]:
    value = read_text(path, "max")
    if value == "max":
        return "max"
    try:
        return int(value)
    except (TypeError, ValueError):
        return "max"


def atomic_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, sort_keys=True, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def load_json(path: pathlib.Path, default: dict) -> dict:
    try:
        with path.open("r", encoding="utf-8") as f:
            value = json.load(f)
        return value if isinstance(value, dict) else default.copy()
    except (OSError, ValueError, TypeError):
        return default.copy()


def default_config() -> dict:
    return {"version": 1, "apps": {}}


def load_config() -> dict:
    cfg = load_json(CONFIG_PATH, default_config())
    cfg.setdefault("version", 1)
    apps = cfg.get("apps", {})
    if not isinstance(apps, dict):
        apps = {}

    # Migrate any identity that was saved while /proc/PID/exe carried Linux's
    # transient " (deleted)" suffix after an in-place package update.  Prefer
    # an already-canonical entry if both forms happen to exist.
    normalized: Dict[str, dict] = {}
    for raw_exe, entry in apps.items():
        exe = normalize_executable(raw_exe)
        if not exe:
            continue
        if exe not in normalized or raw_exe == exe:
            normalized[exe] = entry if isinstance(entry, dict) else {}
    cfg["apps"] = normalized
    return cfg


def save_config_if_changed(cfg: dict) -> bool:
    old = load_json(CONFIG_PATH, {})
    if old == cfg:
        return False
    atomic_json(CONFIG_PATH, cfg)
    return True


def app_label_for_exe(exe: str) -> str:
    exe = normalize_executable(exe)
    base = pathlib.Path(exe).name
    if base in {"brave", "brave-browser", "brave-browser-stable"}:
        return "Brave"
    if base in {"firefox", "firefox-esr"}:
        return "Firefox"
    if base == "spotify":
        return "Spotify"
    return base or "App"


def is_helper_exe(exe: str) -> bool:
    exe = normalize_executable(exe)
    base = pathlib.Path(exe).name
    return base in HELPER_BASENAMES or base.startswith("ld-linux-")


def parse_unified_cgroup(pid: int) -> Optional[str]:
    text = read_text(PROC_ROOT / str(pid) / "cgroup")
    for line in text.splitlines():
        parts = line.split(":", 2)
        if len(parts) == 3 and parts[0] == "0":
            return parts[2]
    return None


def top_app_unit(cgroup_path: str) -> Optional[str]:
    marker = "/app.slice/"
    if marker not in cgroup_path:
        return None
    rest = cgroup_path.split(marker, 1)[1]
    unit = rest.split("/", 1)[0]
    if unit.startswith("app-") and (unit.endswith(".scope") or unit.endswith(".service")):
        return unit
    return None


@dataclass
class ProcInfo:
    pid: int
    exe: str
    comm: str
    unit: str


@dataclass
class UnitInfo:
    unit: str
    directory: str
    current: int
    high: Union[int, str]
    maximum: Union[int, str]
    primary_exe: str
    processes: List[ProcInfo]


def collect_processes() -> Dict[str, List[ProcInfo]]:
    units: Dict[str, List[ProcInfo]] = defaultdict(list)
    try:
        entries = list(PROC_ROOT.iterdir())
    except OSError:
        return units
    for entry in entries:
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            exe = normalize_executable(os.readlink(entry / "exe"))
        except OSError:
            continue
        cg = parse_unified_cgroup(pid)
        if not cg:
            continue
        unit = top_app_unit(cg)
        if not unit:
            continue
        comm = read_text(entry / "comm", pathlib.Path(exe).name)
        units[unit].append(ProcInfo(pid=pid, exe=exe, comm=comm, unit=unit))
    return units


def choose_primary(processes: List[ProcInfo]) -> str:
    if not processes:
        return ""
    real = [p for p in processes if not is_helper_exe(p.exe)]
    source = real if real else processes
    counts = Counter(p.exe for p in source)
    first_pid: Dict[str, int] = {}
    for p in source:
        first_pid[p.exe] = min(first_pid.get(p.exe, p.pid), p.pid)
    return min(counts.keys(), key=lambda exe: (-counts[exe], first_pid[exe], exe))


def collect_units() -> Dict[str, UnitInfo]:
    by_unit = collect_processes()
    result: Dict[str, UnitInfo] = {}
    for unit, processes in by_unit.items():
        directory = APP_SLICE / unit
        if not directory.is_dir():
            continue
        current_text = read_text(directory / "memory.current", "0")
        try:
            current = int(current_text)
        except ValueError:
            current = 0
        result[unit] = UnitInfo(
            unit=unit,
            directory=str(directory),
            current=current,
            high=read_int_or_max(directory / "memory.high"),
            maximum=read_int_or_max(directory / "memory.max"),
            primary_exe=choose_primary(processes),
            processes=processes,
        )
    return result


def units_for_exact_exe(units: Dict[str, UnitInfo], exe: str) -> List[UnitInfo]:
    exe = normalize_executable(exe)
    return [u for u in units.values() if any(normalize_executable(p.exe) == exe for p in u.processes)]


def units_for_primary_exe(units: Dict[str, UnitInfo], exe: str) -> List[UnitInfo]:
    exe = normalize_executable(exe)
    return [u for u in units.values() if normalize_executable(u.primary_exe) == exe]


def unique_process_names(units: Iterable[UnitInfo]) -> List[str]:
    names: List[str] = []
    seen: Set[str] = set()
    for unit in units:
        for p in unit.processes:
            if p.comm not in seen:
                seen.add(p.comm)
                names.append(p.comm)
            if len(names) >= 32:
                return names
    return names


def aggregate(units: List[UnitInfo]) -> dict:
    current = sum(u.current for u in units)
    highs = [u.high for u in units]
    maxes = [u.maximum for u in units]
    high: Union[int, str] = sum(int(v) for v in highs) if highs and all(isinstance(v, int) for v in highs) else "max"
    maximum: Union[int, str] = sum(int(v) for v in maxes) if maxes and all(isinstance(v, int) for v in maxes) else "max"
    return {
        "current": current,
        "high": high,
        "max": maximum,
        "unitCount": len(units),
        "units": [u.unit for u in units],
        "processes": unique_process_names(units),
    }


def validate_limits(high: Union[int, str], maximum: Union[int, str]) -> Tuple[bool, str]:
    try:
        h = int(high)
        m = int(maximum)
    except (TypeError, ValueError):
        return False, "invalid MemoryHigh/MemoryMax"
    if h <= 0:
        return False, "MemoryHigh must be > 0"
    if m <= h:
        return False, "MemoryMax must be greater than MemoryHigh"
    return True, ""


def run_systemctl_set(unit: str, high: Union[int, str], maximum: Union[int, str]) -> Tuple[bool, str]:
    cmd = ["systemctl", "--user", "set-property", "--runtime", unit, f"MemoryHigh={high}", f"MemoryMax={maximum}"]
    try:
        cp = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, str(e)
    if cp.returncode != 0:
        return False, (cp.stderr or cp.stdout or f"systemctl rc={cp.returncode}").strip()
    return True, ""


def soft_plan(units: List[UnitInfo], total_high: int) -> Dict[str, int]:
    if not units:
        return {}
    floor_weight = 512 * MIB
    weights = {u.unit: max(u.current, floor_weight) for u in units}
    weight_sum = sum(weights.values()) or len(units)
    result: Dict[str, int] = {}
    assigned = 0
    ordered = sorted(units, key=lambda u: u.unit)
    for idx, u in enumerate(ordered):
        if idx == len(ordered) - 1:
            allocation = max(1, total_high - assigned)
        else:
            allocation = max(1, round(total_high * weights[u.unit] / weight_sum))
            assigned += allocation
        result[u.unit] = allocation
    return result


def should_update_limit(current_value: Union[int, str], desired: Union[int, str], tolerance: int = 16 * MIB) -> bool:
    if desired == "infinity":
        return current_value != "max"
    if current_value == "max":
        return True
    try:
        return abs(int(current_value) - int(desired)) > tolerance
    except (TypeError, ValueError):
        return True


def enforce_budget(units: List[UnitInfo], high: int, maximum: int, *, force: bool = False) -> Tuple[str, List[str]]:
    valid, error = validate_limits(high, maximum)
    if not valid:
        return "error", [error]
    if not units:
        return "stopped", []

    errors: List[str] = []
    if len(units) == 1:
        u = units[0]
        desired_max: Union[int, str] = maximum if u.current < maximum else "infinity"
        if force or should_update_limit(u.high, high) or should_update_limit(u.maximum, desired_max):
            ok, msg = run_systemctl_set(u.unit, high, desired_max)
            if not ok:
                errors.append(f"{u.unit}: {msg}")
        return ("pending-max" if desired_max == "infinity" else "ok"), errors

    # Multiple sibling cgroups cannot share one real kernel MemoryMax.  Keep
    # MemoryMax unlimited on each sibling and distribute the requested total
    # MemoryHigh across all of them.
    plan = soft_plan(units, high)
    for u in units:
        desired_high = plan[u.unit]
        if force or should_update_limit(u.high, desired_high) or should_update_limit(u.maximum, "infinity"):
            ok, msg = run_systemctl_set(u.unit, desired_high, "infinity")
            if not ok:
                errors.append(f"{u.unit}: {msg}")
    return "soft-only-multi", errors


def clear_budget(units: List[UnitInfo]) -> List[str]:
    errors: List[str] = []
    for u in units:
        ok, msg = run_systemctl_set(u.unit, "infinity", "infinity")
        if not ok:
            errors.append(f"{u.unit}: {msg}")
    return errors


def configured_apps(cfg: dict) -> Dict[str, dict]:
    apps = cfg.get("apps", {})
    return apps if isinstance(apps, dict) else {}


def discover_primary_apps(units: Dict[str, UnitInfo]) -> Dict[str, dict]:
    exes = sorted({u.primary_exe for u in units.values() if u.primary_exe and not is_helper_exe(u.primary_exe)})
    result: Dict[str, dict] = {}
    for exe in exes:
        app_units = units_for_primary_exe(units, exe)
        agg = aggregate(app_units)
        result[exe] = {
            "display": app_label_for_exe(exe),
            "exe": exe,
            "running": True,
            "stale": False,
            "misses": 0,
            **agg,
            "enforcement": "off",
            "desiredHigh": 0,
            "desiredMax": 0,
            "maintain": False,
            "lastSeen": now(),
        }
    return result


def load_state() -> dict:
    return load_json(STATE_PATH, {"backendVersion": "", "generated": 0, "apps": {}, "scan": {}})


def state_app_from_units(exe: str, display: str, app_units: List[UnitInfo], cfg_entry: dict, enforcement: str) -> dict:
    agg = aggregate(app_units)
    maintain = bool(cfg_entry.get("maintain", False))
    try:
        desired_high = int(cfg_entry.get("high", 0))
        desired_max = int(cfg_entry.get("max", 0))
    except (TypeError, ValueError):
        desired_high = desired_max = 0
    valid, _ = validate_limits(desired_high, desired_max)
    if maintain and valid:
        # Expose the configured aggregate budget.  With multiple units the hard
        # max is a target only; enforcement tells the UI that distinction.
        shown_high: Union[int, str] = desired_high
        shown_max: Union[int, str] = desired_max
    else:
        shown_high = agg["high"]
        shown_max = agg["max"]
    return {
        "display": display or app_label_for_exe(exe),
        "exe": exe,
        "running": True,
        "stale": False,
        "misses": 0,
        "current": agg["current"],
        "high": shown_high,
        "max": shown_max,
        "unitCount": agg["unitCount"],
        "units": agg["units"],
        "processes": agg["processes"],
        "enforcement": enforcement,
        "desiredHigh": desired_high,
        "desiredMax": desired_max,
        "maintain": maintain,
        "lastSeen": now(),
    }


def refresh_state(*, force_enforce: bool = False) -> dict:
    cfg = load_config()
    prev = load_state()
    units = collect_units()
    discovered = discover_primary_apps(units)
    apps_out: Dict[str, dict] = {}

    for exe, entry in configured_apps(cfg).items():
        display = str(entry.get("display") or app_label_for_exe(exe))
        app_units = units_for_exact_exe(units, exe)
        enforcement = "off"
        maintain = bool(entry.get("maintain", False))
        try:
            desired_high = int(entry.get("high", 0))
            desired_max = int(entry.get("max", 0))
        except (TypeError, ValueError):
            desired_high = desired_max = 0
        valid, _ = validate_limits(desired_high, desired_max)
        if app_units and maintain and valid:
            enforcement, errors = enforce_budget(app_units, desired_high, desired_max, force=force_enforce)
            # Refresh memory properties only when an enforcement command was attempted.
            if errors:
                enforcement = "error"
            units = collect_units()
            app_units = units_for_exact_exe(units, exe)
        if app_units:
            apps_out[exe] = state_app_from_units(exe, display, app_units, entry, enforcement)
            continue

        old = prev.get("apps", {}).get(exe, {}) if isinstance(prev.get("apps"), dict) else {}
        misses = int(old.get("misses", 0) or 0) + 1
        if old.get("running") and misses < 3:
            kept = dict(old)
            kept.update({"display": display, "exe": exe, "stale": True, "misses": misses, "maintain": maintain,
                         "desiredHigh": desired_high, "desiredMax": desired_max})
            apps_out[exe] = kept
        else:
            apps_out[exe] = {
                "display": display,
                "exe": exe,
                "running": False,
                "stale": False,
                "misses": misses,
                "current": 0,
                "high": desired_high if maintain and valid else "max",
                "max": desired_max if maintain and valid else "max",
                "unitCount": 0,
                "units": [],
                "processes": [],
                "enforcement": "stopped",
                "desiredHigh": desired_high,
                "desiredMax": desired_max,
                "maintain": maintain,
                "lastSeen": old.get("lastSeen", 0),
            }

    # Scanner cache: live apps grouped by primary executable, plus configured
    # targets (including stopped ones).  Configured exact-executable state wins.
    scan = discovered
    for exe, app in apps_out.items():
        scan[exe] = dict(app)

    state = {
        "backendVersion": BACKEND_VERSION,
        "generated": now(),
        "appSlice": str(APP_SLICE),
        "apps": apps_out,
        "scan": scan,
    }
    atomic_json(STATE_PATH, state)
    return state


def update_registration(exe: str, display: str, maintain: bool, high: int, maximum: int) -> bool:
    exe = normalize_executable(exe)
    if not exe:
        return False
    cfg = load_config()
    apps = configured_apps(cfg)
    entry = {
        "display": display or app_label_for_exe(exe),
        "maintain": bool(maintain),
        "high": int(high) if high else 0,
        "max": int(maximum) if maximum else 0,
    }
    if apps.get(exe) == entry:
        return False
    apps[exe] = entry
    cfg["apps"] = apps
    return save_config_if_changed(cfg)


def get_state_app(state: dict, exe: str) -> Optional[dict]:
    exe = normalize_executable(exe)
    apps = state.get("apps", {})
    if isinstance(apps, dict) and exe in apps:
        return apps[exe]
    scan = state.get("scan", {})
    if isinstance(scan, dict):
        return scan.get(exe)
    return None
