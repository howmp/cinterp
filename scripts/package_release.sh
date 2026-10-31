#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="0.1.0"
OUT="$ROOT/build/release"
mkdir -p "$OUT"
build() {
    local target="$1" name="$2" src
    (cd runtime && zig build -Dtarget="$target" -Doptimize=ReleaseSmall >/dev/null)
    case "$target" in
        *windows*) src="runtime/zig-out/bin/cinterp-run.exe" ;;
        *) src="runtime/zig-out/bin/cinterp-run" ;;
    esac
    local dest="$OUT/cinterp-$VERSION-$name"
    mkdir -p "$dest"
    cp "$src" "$dest/"
    cp README.md "$dest/"
    cat > "$dest/VERSION" <<<"$VERSION"
    tar -C "$OUT" -czf "$OUT/cinterp-$VERSION-$name.tar.gz" "cinterp-$VERSION-$name"
    rm -rf "$dest"
    echo "$OUT/cinterp-$VERSION-$name.tar.gz"
}
build x86_64-linux sysv-x86_64
build x86_64-windows-gnu win64-x86_64
build x86-windows-gnu win32-x86
build aarch64-linux-gnu arm64
