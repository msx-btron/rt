#!/bin/sh
# Native rv64 host oracle for a physical RVV 1.0 machine.
# Scalar C99 with vectorizers off, scalar C99 with vectorizers on,
# then the RVV assembly. The comparison libc is this machine's C library.
# Nanoseconds are CLOCK_MONOTONIC on the board, not a QEMU guest clock.
# QEMU stays in scripts/riscv.sh. Do not boot a guest from here.
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-run}" != run ]; then
    echo "riscv-hw: usage: scripts/riscv_hw.sh" >&2
    exit 1
fi

case "$(uname -m)" in
riscv64) ;;
*)
    echo "riscv-hw: this script runs on riscv64 hardware (uname -m is $(uname -m))" >&2
    exit 1
    ;;
esac

if ! command -v clang >/dev/null 2>&1; then
    echo "riscv-hw: clang not found" >&2
    exit 1
fi
CC=clang

isa=$(sed -n 's/^isa[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1)
if [ -z "$isa" ]; then
    isa=$(sed -n 's/.*\<isa[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1)
fi
echo "riscv-hw: uname $(uname -m)"
echo "riscv-hw: isa ${isa:-missing}"
if command -v getconf >/dev/null 2>&1; then
    getconf GNU_LIBC_VERSION || true
fi

single=${isa%%_*}
has_v=0
case "$single" in
*v*) has_v=1 ;;
esac
case "$isa" in
*_zve64*|*_zve32*) has_v=1 ;;
esac
if [ "$has_v" -ne 1 ]; then
    echo "riscv-hw: CPU isa has no V (${isa:-missing}). RVV 1.0 is required." >&2
    exit 1
fi

OBJ=/tmp/rt-riscv-hw
LOG=$OBJ/tables.txt
rm -rf "$OBJ"
mkdir -p "$OBJ"

# Each extra flag is its own argument. The shell does not split them.
cc_s() {
    out=$1
    src=$2
    shift 2
    "$CC" -std=c99 -O2 -Wall -Wextra -Werror -Wno-unused-function \
        -fno-strict-aliasing -fno-builtin -fno-stack-protector \
        -mabi=lp64d -Iinclude \
        "$@" \
        -S -o "$out" "$src"
}

cc_c() {
    out=$1
    src=$2
    shift 2
    "$CC" -std=c99 -O2 -Wall -Wextra -Werror -Wno-unused-function \
        -fno-strict-aliasing -fno-builtin -fno-stack-protector \
        -mabi=lp64d -Iinclude \
        "$@" \
        -c -o "$out" "$src"
}

as_c() {
    out=$1
    src=$2
    shift 2
    "$CC" -mabi=lp64d "$@" -c -o "$out" "$src"
}

link_bin() {
    out=$1
    shift
    "$CC" -mabi=lp64d -o "$out" "$@"
}

need_sym() {
    if ! nm "$1" | grep -w "$2" >/dev/null; then
        echo "riscv-hw: $1 missing $2" >&2
        exit 1
    fi
}

reject_sym() {
    if nm "$1" | grep -w "$2" >/dev/null; then
        echo "riscv-hw: $1 must not define $2" >&2
        exit 1
    fi
}

count_at_least() {
    n=$(grep -c -F "$1" "$3" || true)
    if [ "$n" -lt "$2" ]; then
        echo "riscv-hw: expected at least $2 of [$1], saw $n" >&2
        exit 1
    fi
}

run_table() {
    name=$1
    bin=$2
    echo "======== $name ========"
    set +e
    NO_COLOR=1 TERM=dumb "$bin" > "$OBJ/one.txt"
    ec=$?
    set -e
    cat "$OBJ/one.txt"
    cat "$OBJ/one.txt" >> "$LOG"
    if [ "$ec" -ne 0 ]; then
        echo "riscv-hw: $name exit $ec" >&2
        exit "$ec"
    fi
}

echo "riscv-hw: clang $($CC --version | head -n 1)"
echo "riscv-hw: nanoseconds are CLOCK_MONOTONIC on this board"
echo "riscv-hw: strscpy, strscat, and strpad have no glibc symbol"

echo "riscv-hw: compile scalar (vectorize off)"
cc_s "$OBJ/mem_off.s" src/common/scalar/mem.c \
    -march=rv64gc -fno-vectorize -fno-slp-vectorize
cc_s "$OBJ/string_off.s" src/common/scalar/string.c \
    -march=rv64gc -fno-vectorize -fno-slp-vectorize
if grep -E 'vset|vle[0-9]|vse[0-9]|vlux|vsox' \
    "$OBJ/mem_off.s" "$OBJ/string_off.s"; then
    echo "riscv-hw: scalar-off assembly contains vector opcodes" >&2
    exit 1
fi
cc_c "$OBJ/test_off.o" verify/suite/test_host.c \
    -march=rv64gc -fno-vectorize -fno-slp-vectorize \
    -DRT_TABLE_SCALAR -DRT_LIBC_NAME='"glibc"'
as_c "$OBJ/mem_off.o" "$OBJ/mem_off.s" -march=rv64gc
as_c "$OBJ/string_off.o" "$OBJ/string_off.s" -march=rv64gc
link_bin "$OBJ/test_host_scalar" \
    "$OBJ/test_off.o" "$OBJ/mem_off.o" "$OBJ/string_off.o"

echo "riscv-hw: compile scalar (vectorize on)"
cc_s "$OBJ/mem_on.s" src/common/scalar/mem.c \
    -march=rv64gcv -DRT_VECTORIZE
cc_s "$OBJ/string_on.s" src/common/scalar/string.c \
    -march=rv64gcv -DRT_VECTORIZE
if ! grep -E 'vset|vle[0-9]|vse[0-9]' "$OBJ/mem_on.s" >/dev/null; then
    echo "riscv-hw: scalar-on memory was not vectorized" >&2
    exit 1
fi
cc_c "$OBJ/test_on.o" verify/suite/test_host.c \
    -march=rv64gcv \
    -DRT_TABLE_SCALAR -DRT_VECTORIZE -DRT_LIBC_NAME='"glibc"'
as_c "$OBJ/mem_on.o" "$OBJ/mem_on.s" -march=rv64gcv
as_c "$OBJ/string_on.o" "$OBJ/string_on.s" -march=rv64gcv
link_bin "$OBJ/test_host_scalar_on" \
    "$OBJ/test_on.o" "$OBJ/mem_on.o" "$OBJ/string_on.o"

echo "riscv-hw: compile RVV"
cc_c "$OBJ/test_rvv.o" verify/suite/test_host.c \
    -march=rv64gcv \
    -DRT_TABLE_RVV -DRT_LIBC_NAME='"glibc"'
as_c "$OBJ/mem_rvv.o" src/riscv64/rvv/mem.s -march=rv64gcv
as_c "$OBJ/string_rvv.o" src/riscv64/rvv/string.s -march=rv64gcv
link_bin "$OBJ/test_host_rvv" \
    "$OBJ/test_rvv.o" "$OBJ/mem_rvv.o" "$OBJ/string_rvv.o"

for sym in rt_memcpy_scalar rt_memmove_scalar rt_memset_scalar \
    rt_memcmp_scalar rt_strlen rt_strpad; do
    need_sym "$OBJ/test_host_scalar" "$sym"
    need_sym "$OBJ/test_host_scalar_on" "$sym"
done
reject_sym "$OBJ/test_host_scalar" rt_memcpy_rvv
reject_sym "$OBJ/test_host_scalar_on" rt_memcpy_rvv
for sym in rt_memcpy_rvv rt_memset_rvv rt_memcmp_rvv \
    rt_strlen_rvv rt_strpad_rvv; do
    need_sym "$OBJ/test_host_rvv" "$sym"
done

: > "$LOG"
run_table "scalar riscv64 glibc (vectorize off)" "$OBJ/test_host_scalar"
run_table "scalar riscv64 glibc (vectorize on)" "$OBJ/test_host_scalar_on"
run_table "RVV64 glibc" "$OBJ/test_host_rvv"

count_at_least "vectorize: off" "$LOG" 1
count_at_least "vectorize: on" "$LOG" 1
count_at_least "binary: rvv" "$LOG" 1
count_at_least "== backend: scalar ==" "$LOG" 2
count_at_least "== backend: rvv ==" "$LOG" 1
count_at_least "| memmove " "$LOG" 2
count_at_least "| strscpy          |      N/A |" "$LOG" 3
count_at_least "libc: glibc" "$LOG" 3
echo "riscv-hw: scalar off, scalar on, and RVV ok"
