#!/bin/bash
# 同步共享仓库源码 -> 本地构建副本（规避 virtiofs 元数据 EPERM）
# 用法: bash scripts/ohos/sync-src.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

echo "[sync-src] $QEMU_REPO -> $QEMU_OHOS_SRC"
mkdir -p "$QEMU_OHOS_SRC"
tar cf - --exclude=.git -C "$QEMU_REPO" . | tar xf - -C "$QEMU_OHOS_SRC"
echo "[sync-src] 完成"
