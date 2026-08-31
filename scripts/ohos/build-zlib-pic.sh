#!/bin/bash
# Build a PIC static zlib for the OHOS cross build.
#
# Why: the libz.a shipped by harmonybrew (zlib-ng-compat) is NOT compiled with
# -fPIC, so its objects cannot be linked into the shared libqemu-system-aarch64
# (ld.lld: "relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used ...; recompile
# with -fPIC").  This script rebuilds zlib-1.3.1 with -fPIC using the OHOS clang
# so that zlib can be statically linked into the self-contained .so.
#
# The output ($QEMU_OHOS_ZLIB_PIC/lib/libz.a) is referenced by env.sh when it
# writes the static zlib.pc override.  Run once after a fresh build root
# (e.g. /tmp/qemu-ohos) has been created and before building the shared library.
#
# Usage: bash scripts/ohos/build-zlib-pic.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# zlib-1.3.1 source lives under ohcode-qemu (shared workspace).  Point
# ZLIB_SRC_TAR elsewhere to use a different copy.
ZLIB_SRC_TAR=${ZLIB_SRC_TAR:-/mnt/linux_share/workspace/ohcode-qemu/zlib-1.3.1}
ZLIB_SRC="$QEMU_OHOS_BUILD/zlib-src"
ZLIB_PIC="${QEMU_OHOS_ZLIB_PIC:-$QEMU_OHOS_BUILD/zlib-pic}"

if [ ! -d "$ZLIB_SRC_TAR" ]; then
    echo "[build-zlib-pic] ERROR: zlib source dir not found: $ZLIB_SRC_TAR" >&2
    exit 1
fi

if [ -f "$ZLIB_PIC/lib/libz.a" ]; then
    echo "[build-zlib-pic] already built: $ZLIB_PIC/lib/libz.a"
    exit 0
fi

echo "[build-zlib-pic] copying zlib source -> $ZLIB_SRC"
mkdir -p "$ZLIB_SRC"
cp -r "$ZLIB_SRC_TAR"/. "$ZLIB_SRC"/

echo "[build-zlib-pic] cross-building static libz.a with -fPIC"
bash -c "cd '$ZLIB_SRC' && CC='$CC' CFLAGS='-O2 -fPIC' \
    ./configure --static --prefix='$ZLIB_PIC' \
    && make -j6 && make install" > "$QEMU_OHOS_BUILD/zlib-build.log" 2>&1

if [ ! -f "$ZLIB_PIC/lib/libz.a" ]; then
    echo "[build-zlib-pic] ERROR: build failed, see $QEMU_OHOS_BUILD/zlib-build.log" >&2
    exit 1
fi
echo "[build-zlib-pic] done: $ZLIB_PIC/lib/libz.a"
