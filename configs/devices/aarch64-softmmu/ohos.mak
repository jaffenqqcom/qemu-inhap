# Minimal device configuration for the OHOS (aarch64-softmmu) port.
#
# Used with --without-default-devices (minikconf --allnoconfig).  In allnoconfig
# mode every symbol starts at 'n' and only what is listed here (plus what the
# 'virt' machine Kconfig 'select's) is built, so the machine must be enabled
# explicitly.  The goal is a small shared library that boots a minimal arm64
# Linux guest (OHcode) with:
#   - a serial console (PL011, selected by the virt machine)
#   - an initramfs root filesystem (rootfs.cpio.gz via -initrd / fw_cfg)
#   - host-folder sharing (virtio-9p, mounted with -virtfs local,path=...)
#   - a virtio-serial guest->host command bridge
#   - virtio-net with slirp user-mode networking (TCP hostfwd)
#
# The virt machine itself selects: ARM_GIC, ACPI, ARM_SMMUV3, GPIO, DEVICE_TREE,
# FW_CFG_DMA, PCI_EXPRESS_GENERIC_BRIDGE, PFLASH_CFI01, PL011 (UART), PL031 (RTC),
# PL061 (GPIO), GPIO_PWR, PLATFORM_BUS, SMBIOS.
#
# Everything else (USB, NICs, display, audio, the 32-bit ARM boards, TPM,
# NVDIMM, IOMMUFD, ...) is excluded to keep the shared library minimal.
# Only the OHOS build uses this via --with-devices-aarch64=ohos; the default
# Linux build is unchanged.

# The virt machine (aarch64 generic).  Must be enabled explicitly in allnoconfig.
CONFIG_ARM_VIRT=y

# virtio core and transport.  Both virtio-mmio and virtio-pci are enabled:
# OHcode drives virtio-net-pci / virtio-9p-pci / virtio-serial-pci on the
# virt machine's PCIe bus (gpex host).  CONFIG_PCI is already selected by the
# virt machine (gpex -> PCI_EXPRESS -> PCI), which satisfies VIRTIO_PCI's
# "depends on PCI".
CONFIG_VIRTIO=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_PCI=y

# virtio-block: optional guest block rootfs (not needed for OHcode's initramfs)
CONFIG_VIRTIO_BLK=y

# virtio-net: guest networking (paired with -netdev user, slirp backend)
CONFIG_VIRTIO_NET=y

# virtio-serial: guest->host command bridge (OHcode hostcmd socket)
CONFIG_VIRTIO_SERIAL=y

# virtio-9p: host-folder sharing (9p 'local' backend)
CONFIG_VIRTFS=y
CONFIG_VIRTIO_9P=y

# vhost-user: shared-memory transport for virtio-fs (PoC: replace 9p for the
# performance-critical work-directory share). CONFIG_VHOST_USER is a
# config-host macro produced by configure --enable-vhost-user; VHOST_USER_FS
# selects the vhost-user-fs-pci frontend device, paired with an external
# virtiofsd backend.
CONFIG_VHOST_USER=y
CONFIG_VHOST_USER_FS=y

# pcie-root-port: provides a hotpluggable PCIe bus so runtime device_add of a
# virtio-9p work-directory mount works (the pcie.0 root bus has no hotplug
# handler). Without it QMP device_add fails with "Bus 'pcie.0' does not support
# hotplugging".
CONFIG_PCIE_PORT=y
