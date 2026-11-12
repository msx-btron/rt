#!/bin/sh
# Host test driver. macOS M4 (arm64) and Linux x86-64.
set -eu
cd "$(dirname "$0")"

mode=${1:-test}
os=$(uname -s)
arch=$(uname -m)
cc=${CC:-cc}
cflags="-std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-builtin -I../include"
mkdir -p build

asm32() {
    "$cc" -m32 -c -o build/i386_rep.o ../src/i386/rep/mem.s
    "$cc" -m32 -c -o build/i386_mmx.o ../src/i386/mmx/mem.s
    "$cc" -m32 -c -o build/i386_pc98.o ../src/i386/pc98/mem.s
    "$cc" -m32 -c -o build/i386_pc98_real.o ../src/i386/pc98/mem16.s
    "$cc" -m32 -c -o build/i386_sse.o ../src/i386/sse/mem.s
    echo "asmcheck ok"
}

case "$os:$arch:$mode" in
Darwin:arm64:*|Darwin:aarch64:*)
    "$cc" $cflags -o build/test_mem_arm64 \
        test_mem.c \
        ../src/common/scalar/mem.c \
        ../src/aarch64/neon/mem.S
    ./build/test_mem_arm64
    ;;
Linux:x86_64:test32)
    "$cc" $cflags -m32 -o build/test_mem32 \
        test_mem.c \
        ../src/common/scalar/mem.c \
        ../src/i386/rep/mem.s \
        ../src/i386/mmx/mem.s \
        ../src/i386/pc98/mem.s \
        ../src/i386/sse/mem.s
    ./build/test_mem32
    ;;
Linux:x86_64:*)
    "$cc" $cflags -o build/test_mem64 \
        test_mem.c \
        ../src/common/scalar/mem.c \
        ../src/x86_64/sse2/mem.s \
        ../src/x86_64/avx2/mem.s \
        ../src/x86_64/avx512/mem.s
    ./build/test_mem64
    asm32
    ;;
*)
    echo "No native build for $os $arch ($mode)." >&2
    echo "macOS: Apple Silicon (arm64). Linux: x86-64, or 'make test32' with multilib." >&2
    exit 1
    ;;
esac
