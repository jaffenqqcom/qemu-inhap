# QEMU 编译指导（HarmonyOS）

本文档记录把 QEMU 交叉编译为 HarmonyOS（OHOS）可用的 `libqemu-system-aarch64.so`
的完整流程：编译方法、配置说明、使用与集成方法、已知的坑。

## 一、目标与产物

- **目标**：一个独立的 `libqemu-system-aarch64.so`，可被鸿蒙 HAP 通过 `dlopen`
  加载，在独立线程中运行 `-M virt` 的 ARM64 Linux guest。
- **关键指标**：外部依赖（glib/zlib/slirp 等）全部**静态链入**，`.so` 的
  `NEEDED` 只剩 `libc.so`（系统提供），实现单文件独立交付。
- **功能**：串口（PL011）、initramfs rootfs、virtio-9p 文件夹共享、
  virtio-serial 命令桥、virtio-net + slirp 用户态网络、`fsdev-add` QMP 动态挂载。

## 二、环境要求

- 宿主：Linux aarch64（aarch64 glibc）。
- OHOS NDK：`/mnt/linux_share/workspace/commandline-linux-arm64/sdk/default/openharmony/native/llvm`
  （含 `aarch64-unknown-linux-ohos-clang` 包装器，自动带 musl sysroot）。
- 依赖库：`/mnt/linux_share/.harmonybrew`（OHOS/aarch64-musl 的 glib / pcre2 /
  gettext / libffi / pixman / zlib-ng）。
- zlib-1.3.1 源码：`/mnt/linux_share/workspace/ohcode-qemu/zlib-1.3.1`
  （或通过 `ZLIB_SRC_TAR` 指定其他副本）。
- 构建根：`QEMU_OHOS_BUILD=/tmp/qemu-ohos`（**必须是本地磁盘**，不能用 virtiofs
  共享盘——共享盘对非 root 的 chmod/chown/utimensat 返回 EPERM，configure 的
  venv/pip 与 ninja 依赖这些元数据操作）。
- 源码：仓库 `/mnt/linux_share/workspace/qemu-inhap`（共享盘），构建时由
  `sync-src.sh` 复制到本地副本 `/tmp/qemu-ohos/qemu-src`。

> **备注：当前这台开发机上，环境与依赖已完整就绪。** OHOS NDK、harmonybrew
> 依赖库（glib/pcre2/gettext/libffi/pixman/zlib-ng）、zlib-1.3.1 源码、构建根
> `/tmp/qemu-ohos` 均已在位，无需额外下载或安装任何软件。直接按第三节步骤
> 编译即可；configure 阶段 meson 下载 wrap 子项目源码（libslirp/dtc 等）在本机
> 已有缓存（`/tmp/qemu-ohos/qemu-src/subprojects`），不会重新走网络。

## 三、编译步骤

脚本全部在仓库 `scripts/ohos/` 下。

### 步骤 1：configure（首次构建，或改了配置/设备集之后）

```bash
cd /mnt/linux_share/workspace/qemu-inhap
bash scripts/ohos/configure-ohos.sh
```

`configure-ohos.sh` 内部：
- `source env.sh`：设置工具链、生成修正 prefix 的 `.pc` 覆盖文件（glib/zlib
  指向静态库）、生成 clang/pkg-config 包装脚本。
- 用最小化 `--disable` 列表 + `--enable-slirp` + `--without-default-devices`
  `--with-devices-aarch64=ohos` + `-Dlibqemu=enabled` + `-Dslirp:default_library=static`
  运行 QEMU configure。
- meson 会在这一步**从网络下载 wrap 子项目源码**（libslirp、dtc、
  berkeley-softfloat-3 等），并生成 `build.ninja`。

### 步骤 2：zlib PIC 静态库（首次构建，或 `/tmp/qemu-ohos` 被清空后）

```bash
bash scripts/ohos/build-zlib-pic.sh
```

> 原因：harmonybrew 的 `libz.a` 不是 `-fPIC` 编译的，链进共享库会报
> `relocation R_AARCH64_ADR_PREL_PG_HI21 ... recompile with -fPIC`。
> 该脚本把 zlib-1.3.1 用 OHOS clang 以 `-fPIC` 重新编译成静态库，输出到
> `/tmp/qemu-ohos/zlib-pic/lib/libz.a`。这是流程中唯一需要提前准备的外部依赖。

### 步骤 3：构建

```bash
bash scripts/ohos/build-ohos.sh libqemu-system-aarch64.so
```

`build-ohos.sh` 内部：`sync-src.sh`（复制最新源码到本地副本）→ `ninja`。
不带参数则构建全部目标；传 `libqemu-system-aarch64.so` 只构建共享库。

### 步骤 4：strip（交付时，可选但建议）

```bash
cp /tmp/qemu-ohos/build/libqemu-system-aarch64.so /tmp/qemu-ohos/build/libqemu-system-aarch64-stripped.so
/usr/bin/strip /tmp/qemu-ohos/build/libqemu-system-aarch64-stripped.so
```

> 注意：**不要用 OHOS NDK 的 `llvm-strip`**——它的 `llvm-objcopy` 是个 725 字节
> 脚本（真二进制被改名 `.bak`），普通调用不删 debug 段。用 `/usr/bin/strip`
> （GNU binutils 能处理 aarch64 ELF）或 `llvm-strip --strip-debug --strip-unneeded`。

### 步骤 5：验证

```bash
F=/tmp/qemu-ohos/build/libqemu-system-aarch64-stripped.so
# 1) 依赖只剩系统 libc
readelf -d "$F" | grep NEEDED          # 期望只有 [libc.so]
# 2) 关键符号
nm -D "$F" | grep -E " main$|qmp_fsdev_add|qemu_fsdev_add"
# 3) virtio-*-pci 设备已编译
strings "$F" | grep -E "virtio-(net|9p|serial)-pci"
# 4) 架构/类型
file "$F"                              # ELF 64-bit shared object, aarch64
```

预期：NEEDED 仅 `libc.so`；`main`、`qmp_fsdev_add` 导出；`virtio-net-pci`、
`virtio-9p-pci`、`virtio-serial-pci` 字符串存在。strip 后约 **15.7 MB**。

## 四、使用与集成方法

### 4.1 dlopen 加载

HAP 的 NAPI 层 `dlopen("libqemu-system-aarch64.so")`，`dlsym` 取入口函数后开
独立线程运行。入口符号为 **`main`**（QEMU 的 `qemu-system-aarch64` main）。

```c
typedef int (*qemu_main_fn)(int, char **);
void *h = dlopen("libqemu-system-aarch64.so", RTLD_NOW | RTLD_GLOBAL);
qemu_main_fn qemu_main = (qemu_main_fn)dlsym(h, "main");
std::thread([&]{ qemu_main(argc, argv); }).detach();
```

仓库内有冒烟测试 `scripts/ohos/dlopen-test.c`（真机/交叉编译后运行）。

> 注：OHcode 侧 `qemu_runner.cpp` 用 `dlsym(..., "qemu_system_entry")`。若直接
> 替换 OHcode 的 `.so`，需在 QEMU 源码给 `main` 加一个 `qemu_system_entry`
> 导出别名，或改 OHcode 侧符号名。

### 4.2 命令行参数（对齐 OHcode 的用法）

```text
-M virt -cpu cortex-a57 -m 512M
-kernel <Image> -initrd <rootfs.cpio.gz>
-append "console=ttyAMA0,115200 rdinit=/sbin/init"
-display none -monitor none
-serial file:<console.log>
-netdev user,id=net0,hostfwd=tcp:127.0.0.1:39001-:7681
-device virtio-net-pci,netdev=net0,romfile=
-fsdev local,security_model=mapped-file,id=fsdev0,path=<宿主工作目录>
-device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=usershare
-device virtio-serial-pci,id=virtio-serial0
-chardev socket,path=<hostcmd.sock>,server=on,wait=off,id=hostcmd0
-device virtserialport,chardev=hostcmd0,bus=virtio-serial0.0,name=ohcode.hostcmd
```

这些 PCI 设备依赖 `CONFIG_VIRTIO_PCI=y`（已在 `ohos.mak` 启用）。

### 4.3 动态挂载工作目录（fsdev-add QMP）

QEMU 官方不支持运行时新增 9p export，本仓库打了 `fsdev-add` QMP 命令补丁
（见 `HANDOFF-fsdev-add.md`）。顺序：

1. 启动 QEMU 时带 QMP 通道：
   `-qmp unix:path=<sock>,server=on,wait=off`
2. 创建 fsdev：
   `{"execute":"fsdev-add","arguments":{"id":"fsdev0","path":"<真实路径>","security-model":"mapped-file"}}`
3. 热插拔 virtio-9p 设备：
   `{"execute":"device_add","arguments":{"driver":"virtio-9p-pci","id":"fs0","fsdev":"fsdev0","mount_tag":"user0"}}`
4. guest 内挂载：
   `mount -t 9p -o trans=virtio,version=9p2000.L user0 /mnt/user0`

### 4.4 替换 HAP / 集成

- 把 `libqemu-system-aarch64.so` 放进 HAP 的 libs/资源目录，替换旧 `.so`。
- `module.json5` 的 `requestPermissions` 需声明（`scripts/ohos/output` 产物无鸿蒙
  签名，且经 dlopen 加载）：
  - `LOAD_INDEPENDENT_LIBRARY`（kernel 级）——加载非应用自带 .so
  - `IGNORE_LIBRARY_VALIDATION`（kernel 级）——跳过 .so 校验
  - `ALLOW_WRITABLE_CODE_MEMORY`（kernel 级）——TCG JIT 可写可执行内存
  - `CUSTOM_SANDBOX`、`READ_WRITE_USER_FILE`（system 级）——文件路径访问
  - `INTERNET`、`GET_NETWORK_INFO`（normal 级）——virtio-net 网络
- 旧版依赖库（libslirp/libglib/libpixman/libz/libintl/libpcre2 等）**不再需要**，
  静态链入后可不随 HAP 分发。

## 五、配置说明

### 5.1 设备集（configs/devices/aarch64-softmmu/ohos.mak）

最小化：`CONFIG_ARM_VIRT` + `CONFIG_VIRTIO` + `CONFIG_VIRTIO_MMIO` +
`CONFIG_VIRTIO_PCI` + `CONFIG_VIRTIO_BLK` + `CONFIG_VIRTIO_NET` +
`CONFIG_VIRTIO_SERIAL` + `CONFIG_VIRTFS` + `CONFIG_VIRTIO_9P`。
配合 `--without-default-devices`（minikconf allnoconfig）。

### 5.2 裁剪的功能（configure-ohos.sh 的 --disable）

- 图形/显示：sdl gtk vnc curses opengl virglrenderer spice 等
- 音频：alsa pipewire pa jack coreaudio oss sndio
- 镜像格式：qcow1 qed vdi vpc vmdk bochs cloop dmg vvfat 等（留 raw/qcow2）
- 网络后端：af-xdp l2tpv3 vde netmap vmnet bpf passt（留 user/slirp）
- 远程存储/加密/迁移/模块/工具/USB/vhost/KVM 等

### 5.3 静态链入的依赖

- glib（`libglib-2.0.a`）+ pcre2 + libintl + libffi（harmonybrew，PIC）
- zlib（`/tmp/qemu-ohos/zlib-pic/lib/libz.a`，自编译 PIC）
- libslirp（`subprojects/slirp/libslirp.a`，wrap 构建，`-Dslirp:default_library=static`）
- 系统库 libm.a / libutil.a（musl sysroot）
- pixman 已 `--disable-pixman` 移除

## 六、已知的坑

- **zlib / pixman 静态库非 PIC**：harmonybrew 的 `.a` 不能链进 .so，需自编译
  （zlib 已脚本化；pixman 直接禁用）。
- **llvm-strip 失效**：OHOS NDK 的 `llvm-objcopy` 被改名 `.bak`、只剩脚本，
  普通 strip 不删 debug；用 `/usr/bin/strip`。
- **.pc prefix 是设备路径**：harmonybrew 的 .pc 指向
  `/storage/Users/currentUser/.harmonybrew`，env.sh 用 sed 换成宿主机路径。
- **virtiofs EPERM**：共享盘不能直接构建，必须 `sync-src` 到本地磁盘。
- **VIRTIO_PCI 需要 CONFIG_PCI**：`CONFIG_PCI` 由 virt 机器 select 链
  （gpex → PCI_EXPRESS → PCI）自动提供，ohos.mak 只需 `CONFIG_VIRTIO_PCI=y`。
- **OHOS sysroot 缺宏**：`HWCAP2_CSSC` 需 `#ifdef` 保护（util/cpuinfo-aarch64.c）。

## 七、产物清单（scripts/ohos/output/）

- `libqemu-system-aarch64.so` —— 独立共享库（strip 后约 15.7 MB，NEEDED 仅 libc.so）
- 旧依赖库（libslirp/libglib/libpixman/libz/libintl/libpcre2/libgmodule）：
  **已不需要**，保留仅为兼容旧流程，可清理。
