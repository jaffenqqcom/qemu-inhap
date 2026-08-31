/*
 * dlopen smoke test for libqemu-system-aarch64.so (OHOS/musl).
 *
 * Loads the QEMU shared library, resolves its exported "main" symbol and
 * invokes it with the given arguments, the same way a HAP NAPI layer would
 * start a VM.  Run on-device (or under qemu-aarch64 + musl) after copying
 * libqemu-system-aarch64.so and its dependency .so files next to it.
 *
 * Build (on the host, cross for OHOS):
 *   aarch64-unknown-linux-ohos-clang -o dlopen-test dlopen-test.c -ldl
 *
 * Usage:
 *   ./dlopen-test <path-to-libqemu.so> -- -M virt -cpu cortex-a57 ...
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

typedef int (*qemu_main_fn)(int, char **);

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s <libqemu.so> -- <qemu args...>\n", argv[0]);
        return 2;
    }

    const char *lib_path = argv[1];
    /* Skip to the first argument after "--" */
    int qargc = 0;
    char **qargv = NULL;
    int i;
    for (i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) {
            qargv = &argv[i + 1];
            qargc = argc - (i + 1);
            break;
        }
    }
    if (!qargv) {
        fprintf(stderr, "missing '--' separator\n");
        return 2;
    }

    void *handle = dlopen(lib_path, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        fprintf(stderr, "dlopen(%s) failed: %s\n", lib_path, dlerror());
        return 1;
    }
    fprintf(stderr, "[dlopen-test] loaded %s\n", lib_path);

    qemu_main_fn qemu_main = (qemu_main_fn)dlsym(handle, "main");
    if (!qemu_main) {
        fprintf(stderr, "dlsym(main) failed: %s\n", dlerror());
        return 1;
    }
    fprintf(stderr, "[dlopen-test] resolved main, starting QEMU with %d args\n", qargc);

    return qemu_main(qargc, qargv);
}
