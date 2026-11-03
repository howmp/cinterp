#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
VERSION_MAJOR="${VERSION%%.*}"
OUT="$ROOT/build/release"
rm -rf "$OUT"
mkdir -p "$OUT"

if ! python3 scripts/check_version.py --quiet; then
    echo "error: version sources disagree; refusing to package a release" >&2
    exit 1
fi

# Render packaging/README.release.md.in for one target.
#
# The template has two blocks marked with HTML comments: content that only
# applies to tarballs shipping cinterp-cc, and content for runtime-only
# tarballs. `ships_compiler` is "yes" or "no".
render_readme() {
    local dest="$1" name="$2" runner="$3" ships="$4" target="$5" lib_ext
    case "$target" in
        *windows*) lib_ext="dll" ;;
        *) lib_ext="so" ;;
    esac
    sed -e "s|@VERSION@|$VERSION|g" \
        -e "s|@TARGET@|$name|g" \
        -e "s|@RUNNER@|$runner|g" \
        -e "s|@LIB_EXT@|$lib_ext|g" \
        packaging/README.release.md.in |
        awk -v keep="$ships" '
            /^<!--[[:space:]]*compiler-only[[:space:]]*-->$/  { block = "compiler"; next }
            /^<!--[[:space:]]*\/compiler-only[[:space:]]*-->$/ { block = ""; next }
            /^<!--[[:space:]]*runtime-only[[:space:]]*-->$/   { block = "runtime"; next }
            /^<!--[[:space:]]*\/runtime-only[[:space:]]*-->$/ { block = ""; next }
            {
                if (block == "" ||
                    (block == "compiler" && keep == "yes") ||
                    (block == "runtime" && keep != "yes")) {
                    if ($0 == "" && last_blank) next
                    print
                    last_blank = ($0 == "")
                }
            }
        ' > "$dest/README.md"

    if grep -q '@[A-Z_][A-Z_]*@' "$dest/README.md"; then
        echo "error: unrendered placeholder left in $dest/README.md" >&2
        return 1
    fi
    if [ "$ships" = "yes" ]; then
        grep -q 'bin/cinterp-cc' "$dest/README.md" || {
            echo "error: compiler README does not mention bin/cinterp-cc" >&2
            return 1
        }
    else
        grep -q 'runtime-only tarball' "$dest/README.md" || {
            echo "error: runtime-only README does not say so" >&2
            return 1
        }
    fi
}

copy_common() {
    local dest="$1" name="$2" runner="$3" ships="$4" target="$5" private_libs
    cp LICENSE VERSION "$dest/"
    render_readme "$dest" "$name" "$runner" "$ships" "$target"
    mkdir -p "$dest/docs" "$dest/examples"
    cp docs/*.md "$dest/docs/"
    cp -a examples/. "$dest/examples/"

    case "$target" in
        *windows*) private_libs="" ;;
        *) private_libs="-ldl -lpthread -lm" ;;
    esac

    mkdir -p "$dest/pkgconfig" "$dest/cmake" "$dest/lib/cmake/cinterp" \
        "$dest/rust/cinterp-sys/src" "$dest/rust/cinterp-sys/examples"
    sed -e "s|@VERSION@|$VERSION|g" -e "s|@PRIVATE_LIBS@|$private_libs|g" \
        packaging/cinterp.pc.in > "$dest/pkgconfig/cinterp.pc"
    sed -e "s|@VERSION@|$VERSION|g" -e "s|@VERSION_MAJOR@|$VERSION_MAJOR|g" \
        packaging/cmake/cinterpConfig.cmake.in > "$dest/cmake/cinterpConfig.cmake"
    sed -e "s|@VERSION@|$VERSION|g" -e "s|@VERSION_MAJOR@|$VERSION_MAJOR|g" \
        packaging/cmake/cinterpConfigVersion.cmake.in \
        > "$dest/cmake/cinterpConfigVersion.cmake"
    cp "$dest/cmake/cinterpConfig.cmake" "$dest/cmake/cinterpConfigVersion.cmake" \
        "$dest/lib/cmake/cinterp/"
    sed -e "s|@VERSION@|$VERSION|g" packaging/rust/cinterp-sys/Cargo.toml.in \
        > "$dest/rust/cinterp-sys/Cargo.toml"
    cp packaging/rust/cinterp-sys/build.rs packaging/rust/cinterp-sys/README.md \
        "$dest/rust/cinterp-sys/"
    cp packaging/rust/cinterp-sys/src/lib.rs "$dest/rust/cinterp-sys/src/"
    cp packaging/rust/cinterp-sys/examples/run_hello.rs \
        "$dest/rust/cinterp-sys/examples/"
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
    local target="$1" name="$2" exe ships="no" runner
    (cd runtime && rm -rf zig-out && \
        zig build -Dtarget="$target" -Doptimize=ReleaseSmall -Dkeep-debug=true >/dev/null)
    case "$target" in
        *windows*) exe="cinterp-run.exe" ;;
        *) exe="cinterp-run" ;;
    esac
    runner="$exe"

    local dest="$OUT/cinterp-$VERSION-$name"
    rm -rf "$dest"
    mkdir -p "$dest/include" "$dest/lib"
    cp "runtime/zig-out/bin/$exe" "$dest/"
    cp runtime/zig-out/include/cinterp.h "$dest/include/"
    cp -a runtime/zig-out/lib/. "$dest/lib/"
    if [ "$target" = "x86_64-linux-gnu" ]; then
        (cd compiler && zig build -Doptimize=ReleaseSmall >/dev/null)
        mkdir -p "$dest/bin"
        cp compiler/zig-out/bin/cinterp-cc "$dest/bin/cinterp-cc"
        cp packaging/bin/cinterp.in "$dest/bin/cinterp"
        chmod +x "$dest/bin/cinterp"
        ships="yes"
    fi
    for dll in runtime/zig-out/bin/*.dll; do
        if [ -e "$dll" ]; then cp "$dll" "$dest/"; fi
    done
    copy_common "$dest" "$name" "$runner" "$ships" "$target"
    split_debug "$dest" "$exe" "$target"

    # gen_sbom.py writes THIRD_PARTY_NOTICES.md into compiler tarballs before
    # hashing, so the notice is part of the SBOM file list and the tarball.
    python3 scripts/gen_sbom.py \
        --root "$dest" \
        --output "$dest/SBOM.spdx.json" \
        --version "$VERSION" \
        --target "$name"
    if [ "$ships" = "yes" ] && [ ! -s "$dest/THIRD_PARTY_NOTICES.md" ]; then
        echo "error: $dest is missing THIRD_PARTY_NOTICES.md" >&2
        exit 1
    fi
    if [ "$ships" = "no" ] && [ -e "$dest/THIRD_PARTY_NOTICES.md" ]; then
        echo "error: runtime-only $dest must not ship THIRD_PARTY_NOTICES.md" >&2
        exit 1
    fi
    cp "$dest/SBOM.spdx.json" "$OUT/cinterp-$VERSION-$name.spdx.json"
    tar -C "$OUT" -czf "$OUT/cinterp-$VERSION-$name.tar.gz" "cinterp-$VERSION-$name"
    rm -rf "$dest"
    echo "$OUT/cinterp-$VERSION-$name.tar.gz"
}

build_one x86_64-linux-gnu sysv-x86_64
build_one x86_64-windows-gnu win64-x86_64
build_one x86-windows-gnu win32-x86
build_one aarch64-linux-gnu arm64

(
    cd "$OUT"
    sha256sum ./*.tar.gz ./*.spdx.json > SHA256SUMS
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
