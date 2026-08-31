#!/bin/bash
# QEMU-ohos 构建脚本：同步源码 + ninja 构建
# 用法: bash scripts/ohos/build-ohos.sh [ninja args...]
#   不带参数构建全部；常用: qemu-system-aarch64 libqemu-system-aarch64.so
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

bash "$(dirname "${BASH_SOURCE[0]}")/sync-src.sh"

echo "[build-ohos] ninja 开始: $(date '+%H:%M:%S')"
cd "$QEMU_OHOS_BLD"
ninja -j6 "$@" 2>&1 | tee "$QEMU_OHOS_BUILD/build.log"
echo "[build-ohos] ninja 退出码: ${PIPESTATUS[0]} 结束: $(date '+%H:%M:%S')"
