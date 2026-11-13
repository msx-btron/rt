#!/bin/sh
# Host test driver. One binary per table.
# The scalar table is built twice from the same C99 sources:
#   build/test_host_scalar      vectorizers off
#   build/test_host_scalar_vec  vectorizers on
# Neon, SME, and the x86 simd tables are their own binaries.
# Anchored at the repo root.
set -eu
cd "$(dirname "$0")/.."

mode=${1:-test}
os=$(uname -s)
arch=$(uname -m)
cc=${CC:-cc}
cflags="-std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-builtin -Iinclude"
cflags_off="$cflags -fno-vectorize -fno-slp-vectorize"
cflags_on="$cflags -fvectorize -fslp-vectorize"
mkdir -p build

scalar_src="src/common/scalar/mem.c \
src/common/scalar/string.c \
src/common/scalar/stdlib.c \
src/common/scalar/stdio.c"

suite="verify/suite/test_host.c"

run_bin() {
    bin=$1
    if "$bin"; then
        return 0
    fi
    base=$(basename "$bin")
    cp -f "$bin" "/tmp/$base"
    chmod +x "/tmp/$base"
    "/tmp/$base"
}

asm32() {
    "$cc" -m32 -c -o build/i386_rep.o src/i386/rep/mem.s
    "$cc" -m32 -c -o build/i386_mmx.o src/i386/mmx/mem.s
    "$cc" -m32 -c -o build/i386_pc98.o src/i386/pc98/mem.s
    "$cc" -m32 -c -o build/i386_pc98_real.o src/i386/pc98/mem16.s
    "$cc" -m32 -c -o build/i386_sse.o src/i386/sse/mem.s
    echo "asmcheck ok"
}

build_scalar() {
    # $1 extra -D, $2 output, $3 flags
    # shellcheck disable=SC2086
    "$cc" $3 $1 -o "$2" "$suite" $scalar_src
}

case "$os:$arch:$mode" in
Darwin:arm64:*|Darwin:aarch64:*)
    build_scalar -DRT_TABLE_SCALAR build/test_host_scalar "$cflags_off"
    build_scalar "-DRT_TABLE_SCALAR -DRT_VECTORIZE" build/test_host_scalar_vec "$cflags_on"
    # shellcheck disable=SC2086
    "$cc" $cflags -DRT_TABLE_NEON -o build/test_host_neon "$suite" \
        src/aarch64/neon/mem.S src/aarch64/neon/string.S
    # shellcheck disable=SC2086
    "$cc" $cflags -DRT_TABLE_SME -o build/test_host_sme "$suite" \
        src/aarch64/sme/mem.S
    echo "======== scalar, vectorize off ========"
    run_bin ./build/test_host_scalar
    echo
    echo "======== scalar, vectorize on ========"
    run_bin ./build/test_host_scalar_vec
    echo
    echo "======== neon ========"
    run_bin ./build/test_host_neon
    echo
    echo "======== sme ========"
    run_bin ./build/test_host_sme
    ;;
Linux:x86_64:*)
    build_scalar -DRT_TABLE_SCALAR build/test_host_scalar "$cflags_off"
    build_scalar "-DRT_TABLE_SCALAR -DRT_VECTORIZE" build/test_host_scalar_vec "$cflags_on"
    # shellcheck disable=SC2086
    "$cc" $cflags -DRT_TABLE_SIMD -o build/test_host_simd "$suite" \
        src/x86_64/sse2/mem.s src/x86_64/avx/mem.s \
        src/x86_64/avx2/mem.s src/x86_64/avx512/mem.s
    echo "======== scalar, vectorize off ========"
    run_bin ./build/test_host_scalar
    echo
    echo "======== scalar, vectorize on ========"
    run_bin ./build/test_host_scalar_vec
    echo
    echo "======== simd ========"
    run_bin ./build/test_host_simd
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
# Two Intel machines, Alpine image ≤50MB each, no installer:
#   sh scripts/avx512.sh            # IA-32 (i386/mmx/sse) and EM64T (sse2/avx/avx2/avx512)
#   sh scripts/avx512.sh ia32
#   sh scripts/avx512.sh em64t
