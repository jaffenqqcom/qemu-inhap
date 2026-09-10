#!/bin/bash
# QEMU-ohos 交叉配置脚本：aarch64-softmmu，最小设备集，产物为共享库
# 用法: bash scripts/ohos/configure-ohos.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

mkdir -p "$QEMU_OHOS_BLD"
cd "$QEMU_OHOS_BLD"

# -Wno-unused-command-line-argument / -D__user= : OHOS sysroot 头适配，见 env.sh 注释。
EXTRA_CFLAGS="-Wno-unused-command-line-argument -D__user= -I$GETTEXT_DIR/include"
EXTRA_LDFLAGS="-L$GETTEXT_DIR/lib"

echo "[qemu-ohos] configure 开始，日志 -> $QEMU_OHOS_BLD/configure.log"

# 禁用的功能均为 OHOS 平台用不到的（图形/音频/显示、远程存储、镜像格式、
# 密码库、虚拟化后端、迁移、vhost-*、USB 等）；slirp 用户态网络保留，
# 最小设备集见 configs/devices/aarch64-softmmu/ohos.mak。
timeout 900 "$QEMU_OHOS_SRC/configure" \
  --target-list=aarch64-softmmu \
  --cross-prefix=aarch64-unknown-linux-ohos- \
  --disable-werror --disable-docs --disable-tools --disable-guest-agent \
  --disable-sdl --disable-gtk --disable-vnc --disable-curses \
  --disable-modules --disable-kvm --disable-hvf --disable-whpx \
  --disable-multiprocess --disable-vfio-user-server --disable-seccomp --disable-bzip2 \
  --enable-vhost-user \
  --disable-vhost-kernel --disable-vhost-net --disable-vhost-vdpa \
  --disable-vhost-user-blk-server --disable-vhost-crypto \
  --disable-libusb \
  --enable-slirp \
  --disable-af-xdp --disable-l2tpv3 --disable-vde --disable-netmap --disable-vmnet \
  --disable-bpf --disable-passt --disable-slirp-smbd \
  --disable-bochs --disable-cloop --disable-dmg --disable-parallels \
  --disable-qcow1 --disable-qed --disable-vdi --disable-vpc --disable-vvfat \
  --disable-vhdx --disable-vmdk --disable-snappy --disable-lzo --disable-lzfse \
  --disable-zstd \
  --disable-blkio --disable-libiscsi --disable-libnfs --disable-rbd \
  --disable-curl --disable-libssh --disable-fuse --disable-fuse-lseek --disable-mpath \
  --disable-gnutls --disable-gcrypt --disable-nettle --disable-crypto-afalg \
  --disable-tpm --disable-xen --disable-xen-pci-passthrough --disable-cap-ng \
  --disable-numa --disable-hv-balloon --disable-nitro --disable-igvm \
  --disable-mshv --disable-nvmm --disable-pvg --disable-selinux \
  --disable-auth-pam --disable-membarrier --disable-linux-aio --disable-linux-io-uring \
  --disable-alsa --disable-pipewire --disable-pa --disable-jack \
  --disable-coreaudio --disable-oss --disable-sndio --disable-opengl \
  --disable-virglrenderer --disable-rutabaga-gfx --disable-sdl-image --disable-pixman \
  --disable-dbus-display --disable-spice --disable-spice-protocol \
  --disable-smartcard --disable-vnc-jpeg --disable-vnc-sasl --disable-vte \
  --disable-xkbcommon --disable-canokey --disable-brlapi --disable-u2f \
  --disable-rdma --disable-colo-proxy --disable-replication \
  --disable-capstone --disable-hexagon-idef-parser --disable-qom-cast-debug \
  --disable-relocatable --disable-plugins --disable-sparse \
  --without-default-devices \
  --with-devices-aarch64=ohos \
  --extra-cflags="$EXTRA_CFLAGS" \
  --extra-ldflags="$EXTRA_LDFLAGS" \
  -Dlibqemu=enabled \
  -Db_staticpic=true \
  -Dslirp:default_library=static \
  > "$QEMU_OHOS_BLD/configure.log" 2>&1

echo "[qemu-ohos] configure 退出码: $?"
