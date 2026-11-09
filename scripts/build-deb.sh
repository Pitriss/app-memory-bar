#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION=${1:-}
if [ -z "$VERSION" ]; then
    VERSION=$(python3 -c 'import json; print(json.load(open("metadata.json"))["KPlugin"]["Version"])')
fi
VERSION=${VERSION#v}

META_VERSION=$(python3 -c 'import json; print(json.load(open("metadata.json"))["KPlugin"]["Version"])')
[ "$META_VERSION" = "$VERSION" ] || { printf 'ERROR: metadata version %s != requested %s\n' "$META_VERSION" "$VERSION" >&2; exit 1; }

for path in metadata.json contents debian LICENSE README.md scripts/app-memory-bar-migrate systemd docs/man/man1/app-memory-bar-migrate.1; do
    [ -e "$ROOT/$path" ] || { printf 'ERROR: required packaging path missing: %s\n' "$path" >&2; exit 1; }
done

BUILDROOT="$ROOT/.tmp/deb-build"
SRC="$BUILDROOT/app-memory-bar-$VERSION"
OUT="$BUILDROOT/out"
rm -rf "$BUILDROOT"
mkdir -p "$SRC" "$OUT"

# Stage the current working tree, not HEAD. This makes local package tests work
# before the packaging changes are committed, while still copying only the
# files that belong in the Debian source tree.
cp -a "$ROOT/metadata.json" "$ROOT/contents" "$ROOT/debian" "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/systemd" "$SRC/"
mkdir -p "$SRC/debian" "$SRC/scripts" "$SRC/docs/man/man1"
cp -a "$ROOT/scripts/app-memory-bar-migrate" "$SRC/scripts/"
cp -a "$ROOT/docs/man/man1/app-memory-bar-migrate.1" "$SRC/docs/man/man1/"

cat > "$SRC/debian/changelog" <<EOF_CHANGELOG
plasma-widget-app-memory-bar ($VERSION) unstable; urgency=medium

  * App Memory Bar $VERSION release.

 -- Pitriss <5106460+Pitriss@users.noreply.github.com>  $(date -R)
EOF_CHANGELOG

(
    cd "$SRC"
    # stdout is reserved for the final .deb path so callers can safely use
    # deb="$(./scripts/build-deb.sh VERSION)". Keep the build log visible on stderr.
    dpkg-buildpackage -us -uc -b >&2
)

find "$BUILDROOT" -maxdepth 1 -type f -name 'plasma-widget-app-memory-bar_*_all.deb' -exec cp -f {} "$OUT/" \;
DEB=$(find "$OUT" -maxdepth 1 -type f -name 'plasma-widget-app-memory-bar_*_all.deb' -print -quit)
[ -n "$DEB" ] || { printf 'ERROR: .deb not produced\n' >&2; exit 1; }

printf '%s\n' "$DEB"
