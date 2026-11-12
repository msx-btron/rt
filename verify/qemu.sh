#!/bin/sh
# Vintage i386 profiles under qemu-user (static binary).
#   sh qemu.sh pentium3   # scalar + i386 + mmx + sse   (P3)
#   sh qemu.sh pentium2   # scalar + i386 + mmx         (P2)
#   sh qemu.sh native     # host run.sh
#   sh qemu.sh all        # P2 + P3
#
# Requires: Linux x86_64 or i386 host, gcc -m32, qemu-i386.
# Apple Silicon / ARM cannot assemble or run i386 Intel asm natively.
set -eu
cd "$(dirname "$0")"

host_arch=$(uname -m 2>/dev/null || echo unknown)
case "$host_arch" in
x86_64|i386|i686|amd64) ;;
*)
    echo "qemu i386 profiles need an x86 host (found: $host_arch)." >&2
    echo "On macOS ARM use a Linux VM/container with qemu-user + gcc-multilib." >&2
    echo "Native Apple Silicon path:  make   → tables: scalar + neon" >&2
    exit 1
    ;;
esac

if ! command -v qemu-i386 >/dev/null 2>&1; then
    echo "qemu-i386 not found. Install qemu-user (Linux) first." >&2
    exit 1
fi

# Need a C compiler that can target i386
cc=${CC:-cc}
if ! echo 'int main(void){return 0;}' | $cc -m32 -x c - -o /tmp/rt_m32_probe 2>/dev/null; then
    echo "cc -m32 failed. Install gcc-multilib / libc6-dev-i386." >&2
    exit 1
fi

cflags="-std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-builtin -I../include"
scalar="../src/common/scalar/mem.c ../src/common/scalar/string.c \
../src/common/scalar/stdlib.c ../src/common/scalar/stdio.c"
mkdir -p build
target=${1:-pentium3}

build_i386_static() {
    $cc $cflags -m32 -static -o build/test_host32s test_host.c $scalar \
        ../src/i386/rep/mem.s \
        ../src/i386/mmx/mem.s \
        ../src/i386/sse/mem.s
    # Some sandboxes mark the workspace noexec — run from /tmp.
    cp -f build/test_host32s /tmp/rt_test_host32s
    chmod +x /tmp/rt_test_host32s
}

run_qemu_i386() {
    cpu=$1
    echo "======== qemu-i386 -cpu $cpu ========"
    qemu-i386 -cpu "$cpu" /tmp/rt_test_host32s
}

case "$target" in
pentium3|p3)
    build_i386_static
    run_qemu_i386 pentium3
    ;;
pentium2|p2)
    build_i386_static
    run_qemu_i386 pentium2
    ;;
all)
    build_i386_static
    run_qemu_i386 pentium2
    echo
    run_qemu_i386 pentium3
    ;;
native|host)
    sh ./run.sh
    ;;
*)
    echo "usage: $0 {pentium3|pentium2|all|native}" >&2
    echo "  pentium3 → full-scope tables for scalar + i386 + mmx + sse" >&2
    echo "  pentium2 → full-scope tables for scalar + i386 + mmx" >&2
    exit 1
    ;;
esac
