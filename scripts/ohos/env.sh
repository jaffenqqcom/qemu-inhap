#!/bin/bash
# QEMU-ohos 交叉编译环境（qemu-inhap -> libqemu-system-aarch64.so）
#
# 用法: source scripts/ohos/env.sh
#
# 说明:
#   构建根目录 QEMU_OHOS_BUILD 必须放在本地磁盘（默认 /tmp/qemu-ohos）。
#   原因: /mnt/linux_share 是 virtiofs 共享盘，对非 root 的 chmod/chown/
#   utimensat 返回 EPERM，而 configure 的 venv/pip 与 ninja 依赖这些元数据
#   操作（与 warp-ohos 构建到 $HOME/.ohos-mounts 同理）。
#   可用环境变量 QEMU_OHOS_BUILD 覆盖默认路径。

set -euo pipefail

# ---------- 仓库与构建根 ----------
QEMU_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QEMU_OHOS_BUILD="${QEMU_OHOS_BUILD:-/tmp/qemu-ohos}"
QEMU_OHOS_SRC="$QEMU_OHOS_BUILD/qemu-src"     # 共享仓库的本地副本
QEMU_OHOS_BLD="$QEMU_OHOS_BUILD/build"        # meson/ninja 构建目录
QEMU_OHOS_PC="$QEMU_OHOS_BUILD/pkgconfig"     # 修正 prefix 的 .pc 覆盖目录
QEMU_OHOS_BIN="$QEMU_OHOS_BUILD/bin"          # clang/meson/pkg-config 包装脚本

# ---------- OHOS NDK 工具链 ----------
export LLVM=/mnt/linux_share/workspace/commandline-linux-arm64/sdk/default/openharmony/native/llvm
export OHOS_TARGET=aarch64-unknown-linux-ohos
export CC="$QEMU_OHOS_BIN/$OHOS_TARGET-clang"
export CXX="$QEMU_OHOS_BIN/$OHOS_TARGET-clang++"
export AR="$LLVM/bin/llvm-ar"
export RANLIB="$LLVM/bin/llvm-ranlib"
export STRIP="$LLVM/bin/llvm-strip"

# ---------- 依赖 (harmonybrew, aarch64 OHOS musl) ----------
export HB=/mnt/linux_share/.harmonybrew
export GETTEXT_DIR="$HB/Cellar/gettext/1.0"
export PKG_CONFIG_PATH="$QEMU_OHOS_PC"
export PATH="$QEMU_OHOS_BIN:$PATH"

mkdir -p "$QEMU_OHOS_BUILD" "$QEMU_OHOS_PC" "$QEMU_OHOS_BIN"

# ---------- 生成修正 prefix 的 .pc 覆盖文件 ----------
# harmonybrew 的 .pc prefix 指向设备路径 /storage/Users/currentUser/...，
# 这里 sed 换成宿主机真实路径后放入 PKG_CONFIG_PATH。

# Static-link the core deps (glib/zlib) into libqemu-system-aarch64.so so the
# deliverable depends only on the system libc.  glib's harmonybrew .a is PIC;
# zlib's bundled libz.a is NOT PIC (cannot be linked into a shared object), so
# a PIC libz.a is built separately by build-zlib-pic.sh into $QEMU_OHOS_ZLIB_PIC.
staticize_pc() {
  local pc="$1" libs="$2"
  local src
  src=$(find "$HB/Cellar" -path "*/lib/pkgconfig/$pc.pc" 2>/dev/null | head -1)
  if [ -n "$src" ]; then
    sed -e 's#/storage/Users/currentUser/.harmonybrew#/mnt/linux_share/.harmonybrew#g' \
        -e "s#^Libs:.*#Libs: $libs#" \
        "$src" > "$QEMU_OHOS_PC/$pc.pc"
  fi
}

ZLIB_PIC="${QEMU_OHOS_ZLIB_PIC:-/tmp/qemu-ohos/zlib-pic}"
GLIB_A=$(find "$HB/Cellar/glib" -name "libglib-2.0.a" 2>/dev/null | head -1)
PCRE2_A=$(find "$HB/Cellar/pcre2" -name "libpcre2-8.a" 2>/dev/null | head -1)
INTL_A=$(find "$HB/Cellar/gettext" -name "libintl.a" 2>/dev/null | head -1)
FFI_A=$(find "$HB/Cellar/libffi" -name "libffi.a" 2>/dev/null | head -1)

# glib static lib pulls in pcre2/intl/ffi; referenced libs come last.
staticize_pc glib-2.0  "$GLIB_A $PCRE2_A $INTL_A $FFI_A -lm"
staticize_pc zlib      "$ZLIB_PIC/lib/libz.a"

# Remaining .pc keep the shared (dynamic) .so form.
for pc in gmodule-export-2.0 gmodule-no-export-2.0 gobject-2.0 gio-2.0 \
          gthread-2.0 pixman-1 libpcre2-8 libffi; do
  src=$(find "$HB/Cellar" -path "*/lib/pkgconfig/$pc.pc" 2>/dev/null | head -1)
  if [ -n "$src" ] && [ ! -f "$QEMU_OHOS_PC/$pc.pc" ]; then
    sed 's#/storage/Users/currentUser/.harmonybrew#/mnt/linux_share/.harmonybrew#g' \
      "$src" > "$QEMU_OHOS_PC/$pc.pc"
  fi
done

# ---------- 生成 clang/pkg-config 包装脚本 ----------
# 1) clang: 在参数末尾追加 -Wno-unused-command-line-argument，使它在 meson 探测
#    自带的 -Werror=unused-command-line-argument 之后生效（OHOS clang 为 target
#    自动加的 -L<clang>/lib/<triple> 在纯编译阶段会触发该告警）。
# 2) pkg-config: configure 按 --cross-prefix 推导的 pkg-config 名实际调用系统版。
for tool in aarch64-unknown-linux-ohos-clang aarch64-unknown-linux-ohos-clang++; do
  if [ ! -f "$QEMU_OHOS_BIN/$tool" ]; then
    printf '#!/bin/bash\nexec %s/bin/%s "$@" -Wno-unused-command-line-argument\n' \
      "$LLVM" "$tool" > "$QEMU_OHOS_BIN/$tool"
    chmod +x "$QEMU_OHOS_BIN/$tool"
  fi
done
if [ ! -f "$QEMU_OHOS_BIN/aarch64-unknown-linux-ohos-pkg-config" ]; then
  printf '#!/bin/bash\nexec /usr/bin/pkg-config "$@"\n' \
    > "$QEMU_OHOS_BIN/aarch64-unknown-linux-ohos-pkg-config"
  chmod +x "$QEMU_OHOS_BIN/aarch64-unknown-linux-ohos-pkg-config"
fi

echo "[qemu-ohos] QEMU_REPO=$QEMU_REPO"
echo "[qemu-ohos] QEMU_OHOS_BUILD=$QEMU_OHOS_BUILD"
echo "[qemu-ohos] CC=$CC"
