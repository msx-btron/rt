#!/bin/sh
# Host test driver. macOS M4 (arm64) and Linux x86-64.
# Anchored at the repo root. Output is build/test_host.
set -eu
cd "$(dirname "$0")/.."

mode=${1:-test}
os=$(uname -s)
arch=$(uname -m)
cc=${CC:-cc}
cflags="-std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-builtin -Iinclude"
mkdir -p build

scalar_src="src/common/scalar/mem.c \
src/common/scalar/string.c \
src/common/scalar/stdlib.c \
src/common/scalar/stdio.c"

suite="verify/suite/test_host.c"

run_bin() {
    bin=$1
    if "$bin" 2>/dev/null; then
        return 0
    fi
    cp -f "$bin" /tmp/rt_test_host
    chmod +x /tmp/rt_test_host
    /tmp/rt_test_host
}

asm32() {
    "$cc" -m32 -c -o build/i386_rep.o src/i386/rep/mem.s
    "$cc" -m32 -c -o build/i386_mmx.o src/i386/mmx/mem.s
    "$cc" -m32 -c -o build/i386_pc98.o src/i386/pc98/mem.s
    "$cc" -m32 -c -o build/i386_pc98_real.o src/i386/pc98/mem16.s
    "$cc" -m32 -c -o build/i386_sse.o src/i386/sse/mem.s
    echo "asmcheck ok"
}

case "$os:$arch:$mode" in
Darwin:arm64:*|Darwin:aarch64:*)
    "$cc" $cflags -o build/test_host "$suite" $scalar_src \
        src/aarch64/neon/mem.S src/aarch64/neon/string.S
    run_bin ./build/test_host
    ;;
Linux:x86_64:*)
    "$cc" $cflags -o build/test_host "$suite" $scalar_src \
        src/x86_64/sse2/mem.s src/x86_64/avx2/mem.s src/x86_64/avx512/mem.s
    run_bin ./build/test_host
    asm32
    ;;
*)
    echo "No native build for $os $arch ($mode)." >&2
    exit 1
    ;;
esac

# For vintage i386 profiles under QEMU:
#   sh scripts/qemu.sh pentium3   # scalar + i386 + mmx + sse
#   sh scripts/qemu.sh all
