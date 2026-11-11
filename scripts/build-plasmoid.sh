#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' "$ROOT/metadata.json")
OUTDIR="$ROOT/.plasmoids"
OUT="$OUTDIR/app-memory-bar-$VERSION.plasmoid"
STAGE="$ROOT/.tmp/plasmoid-build"
mkdir -p "$OUTDIR"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$ROOT/metadata.json" "$ROOT/contents" "$ROOT/LICENSE" "$ROOT/README.md" "$STAGE/"
python3 "$ROOT/scripts/compile-translations.py" "$ROOT/po" "$STAGE/contents/locale"
rm -f "$OUT"
(
    cd "$STAGE"
    zip -qr "$OUT" metadata.json contents LICENSE README.md
)
printf '%s\n' "$OUT"
