#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
OUT="$ROOT/build/release"
rm -rf "$OUT"
mkdir -p "$OUT"

copy_common() {
    local dest="$1"
    cp LICENSE THIRD_PARTY_NOTICES.md README.md VERSION "$dest/"
    mkdir -p "$dest/docs" "$dest/compiler" "$dest/examples"
    cp docs/*.md "$dest/docs/"
    cp -a examples/. "$dest/examples/"
    cp -a compiler/src "$dest/compiler/"
    cp compiler/pyproject.toml "$dest/compiler/"
    find "$dest/compiler" \( -type d -name __pycache__ -o -type d -name '*.egg-info' \) \
        -prune -exec rm -rf {} +

    mkdir -p "$dest/bin" "$dest/pkgconfig" "$dest/cmake" \
        "$dest/rust/cinterp-sys/src"
    cp packaging/bin/cinterp.in "$dest/bin/cinterp"
    chmod +x "$dest/bin/cinterp"
    sed "s/@VERSION@/$VERSION/g" packaging/cinterp.pc.in \
        > "$dest/pkgconfig/cinterp.pc"
    sed "s/@VERSION@/$VERSION/g" packaging/cmake/cinterpConfig.cmake.in \
        > "$dest/cmake/cinterpConfig.cmake"
    sed "s/@VERSION@/$VERSION/g" packaging/rust/cinterp-sys/Cargo.toml.in \
        > "$dest/rust/cinterp-sys/Cargo.toml"
    cp packaging/rust/cinterp-sys/build.rs packaging/rust/cinterp-sys/README.md \
        "$dest/rust/cinterp-sys/"
    cp packaging/rust/cinterp-sys/src/lib.rs "$dest/rust/cinterp-sys/src/"
}

split_debug() {
    local dest="$1" exe="$2" target="$3" oc=""
    case "$target" in
        aarch64-*) oc="$(command -v aarch64-linux-gnu-objcopy || command -v objcopy || true)" ;;
        *windows*) oc="$(command -v x86_64-w64-mingw32-objcopy || command -v objcopy || true)" ;;
        *) oc="$(command -v objcopy || true)" ;;
    esac
    if [ -z "$oc" ]; then
        echo "warning: objcopy not found; shipping unstripped $exe" >&2
        return
    fi
    mkdir -p "$dest/debug"
    "$oc" --only-keep-debug "$dest/$exe" "$dest/debug/$exe.debug"
    if [ ! -s "$dest/debug/$exe.debug" ]; then
        rm -f "$dest/debug/$exe.debug"
        rmdir "$dest/debug" 2>/dev/null || true
        return
    fi
    "$oc" --strip-all "$dest/$exe" 2>/dev/null || true
    if file "$dest/$exe" | grep -q ELF; then
        (cd "$dest" && "$oc" --add-gnu-debuglink="debug/$exe.debug" "$exe") 2>/dev/null || true
        "$oc" --remove-section=.eh_frame --remove-section=.eh_frame_hdr \
            "$dest/$exe" 2>/dev/null || true
    fi
}

build_one() {
    local target="$1" name="$2" exe
    (cd runtime && rm -rf zig-out && \
        zig build -Dtarget="$target" -Doptimize=ReleaseSmall -Dkeep-debug=true >/dev/null)
    case "$target" in
        *windows*) exe="cinterp-run.exe" ;;
        *) exe="cinterp-run" ;;
    esac

    local dest="$OUT/cinterp-$VERSION-$name"
    rm -rf "$dest"
    mkdir -p "$dest/include" "$dest/lib"
    cp "runtime/zig-out/bin/$exe" "$dest/"
    cp runtime/zig-out/include/cinterp.h "$dest/include/"
    cp -a runtime/zig-out/lib/. "$dest/lib/"
    for dll in runtime/zig-out/bin/*.dll; do
        if [ -e "$dll" ]; then cp "$dll" "$dest/"; fi
    done
    copy_common "$dest"
    split_debug "$dest" "$exe" "$target"

    python3 scripts/gen_sbom.py \
        --root "$dest" \
        --output "$dest/SBOM.spdx.json" \
        --version "$VERSION" \
        --target "$name"
    cp "$dest/SBOM.spdx.json" "$OUT/cinterp-$VERSION-$name.spdx.json"
    tar -C "$OUT" -czf "$OUT/cinterp-$VERSION-$name.tar.gz" "cinterp-$VERSION-$name"
    rm -rf "$dest"
    echo "$OUT/cinterp-$VERSION-$name.tar.gz"
}

build_one x86_64-linux-gnu sysv-x86_64
build_one x86_64-windows-gnu win64-x86_64
build_one x86-windows-gnu win32-x86
build_one aarch64-linux-gnu arm64

if python3 -c "import setuptools" >/dev/null 2>&1; then
    python3 -m pip wheel --no-deps --no-build-isolation ./compiler -w "$OUT" >/dev/null
else
    python3 -m pip wheel --no-deps ./compiler -w "$OUT" >/dev/null
fi

(
    cd "$OUT"
    sha256sum ./*.tar.gz ./*.whl ./*.spdx.json > SHA256SUMS
)

if [ -n "${CINTERP_GPG_KEY:-}" ]; then
    gpg --batch --yes --armor --local-user "$CINTERP_GPG_KEY" \
        --detach-sign "$OUT/SHA256SUMS"
    gpg --armor --export "$CINTERP_GPG_KEY" > "$OUT/KEYS.asc"
    echo "signed SHA256SUMS with $CINTERP_GPG_KEY"
else
    echo "SHA256SUMS written unsigned (set CINTERP_GPG_KEY to sign)"
fi

echo "release artifacts in $OUT"
ls -1 "$OUT"
