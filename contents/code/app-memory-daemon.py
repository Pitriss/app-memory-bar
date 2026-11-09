#!/usr/bin/python3
from __future__ import annotations

import signal
import sys
import threading

from app_memory_backend import BACKEND_VERSION, refresh_state

wake = threading.Event()
stop = threading.Event()


def on_hup(_signum, _frame):
    wake.set()


def on_stop(_signum, _frame):
    stop.set()
    wake.set()


signal.signal(signal.SIGHUP, on_hup)
signal.signal(signal.SIGTERM, on_stop)
signal.signal(signal.SIGINT, on_stop)

print(f"app-memory-bar backend {BACKEND_VERSION} starting", flush=True)
while not stop.is_set():
    try:
        refresh_state()
    except Exception as exc:
        print(f"refresh failed: {exc!r}", file=sys.stderr, flush=True)
    wake.wait(2.0)
    wake.clear()
print("app-memory-bar backend stopping", flush=True)
