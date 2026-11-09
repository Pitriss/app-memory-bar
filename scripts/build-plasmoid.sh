#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' "$ROOT/metadata.json")
OUTDIR="$ROOT/.plasmoids"
OUT="$OUTDIR/app-memory-bar-$VERSION.plasmoid"
mkdir -p "$OUTDIR"
rm -f "$OUT"
(
    cd "$ROOT"
    zip -qr "$OUT" metadata.json contents LICENSE README.md
)
printf '%s\n' "$OUT"
