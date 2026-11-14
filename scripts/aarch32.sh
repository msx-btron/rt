#!/bin/sh
# AArch32 freestanding contracts. One guest per instruction stream:
#   arm1176  ARMv6 ARM, Pi 1 / Zero / CM1, raspi0
#   a32      AArch32 NEON, Pi 2/3/4 and STM32MP15, virt A7 and A15
#   m0       Thumb-1, STM32 M0/M0+, microbit
#   m3 m4    Thumb-2 integer, mps2-an385 / an386
#   m7       Thumb-2 + PLD, mps2-an500
#   m33      ARMv8-M Mainline, mps2-an505
#   m55      Helium, mps3-an547
# Pi 5 is AArch64. ESP32 is Xtensa or RISC-V. Neither is built here.
# Guest times are not silicon. The bench prints N/A for both clocks.
set -e
cd "$(dirname "$0")/.."

if [ -x /opt/homebrew/opt/llvm/bin/clang ]; then
    CLANG=/opt/homebrew/opt/llvm/bin/clang
else
    CLANG=clang
fi
if [ -x /opt/homebrew/bin/ld.lld ]; then
    LD=/opt/homebrew/bin/ld.lld
else
    LD=ld.lld
fi
QEMU=${QEMU:-qemu-system-arm}
command -v "$QEMU" >/dev/null 2>&1 || {
    echo "aarch32: $QEMU not on PATH"
    exit 1
}

OUT=build/aarch32
rm -rf "$OUT"
mkdir -p "$OUT"
SRC=src/aarch32
A32=verify/suite/a32
CF="-std=c99 -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector -fno-strict-aliasing -mfloat-abi=soft"

run_guest() {
    name=$1
    elf=$2
    shift 2
    echo "aarch32: $name"
    python3 - "$name" "$elf" "$@" << 'PY'
import re, subprocess, sys
name, elf = sys.argv[1], sys.argv[2]
cmd = sys.argv[3:]
try:
    p = subprocess.run(cmd, timeout=40, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
except subprocess.TimeoutExpired as e:
    sys.stdout.buffer.write(e.stdout or b"")
    sys.stderr.write("aarch32: %s TIMEOUT\n" % name)
    sys.exit(124)
out = p.stdout or b""
sys.stdout.buffer.write(out)
if not out.endswith(b"\n"):
    sys.stdout.buffer.write(b"\n")
text = out.decode("utf-8", "replace")
if p.returncode != 0 or not re.search(r"(?m)^TOTAL .* fail 0$", text):
    sys.stderr.write("aarch32: %s exit %s\n" % (name, p.returncode))
    sys.exit(1)
PY
}

build_m() {
    suf=$1
    target=$2
    cpu=$3
    mem=$4
    str=$5
    ld=$6
    extra=$7
    $CLANG -target "$target" -mcpu="$cpu" -mthumb $CF $extra \
        -c -o "$OUT/bench-$suf.o" verify/suite/a32_bench.c -DRT_SUF="$suf"
    $CLANG -target "$target" -mcpu="$cpu" -mthumb $extra \
        -c -o "$OUT/start-$suf.o" "$A32/m_start.S"
    $CLANG -target "$target" -mcpu="$cpu" -mthumb \
        -c -o "$OUT/mem-$suf.o" "$mem"
    $CLANG -target "$target" -mcpu="$cpu" -mthumb \
        -c -o "$OUT/str-$suf.o" "$str"
    $LD -T "$ld" -o "$OUT/$suf.elf" \
        "$OUT/start-$suf.o" "$OUT/bench-$suf.o" \
        "$OUT/mem-$suf.o" "$OUT/str-$suf.o"
}

build_a() {
    suf=$1
    target=$2
    cpu=$3
    fpu=$4
    mem=$5
    str=$6
    ld=$7
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm $CF \
        -c -o "$OUT/bench-$suf.o" verify/suite/a32_bench.c -DRT_SUF="$suf"
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm \
        -c -o "$OUT/start-$suf.o" "$A32/a_start.S"
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm \
        -c -o "$OUT/mem-$suf.o" "$mem"
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm \
        -c -o "$OUT/str-$suf.o" "$str"
    $LD -T "$ld" -o "$OUT/$suf.elf" \
        "$OUT/start-$suf.o" "$OUT/bench-$suf.o" \
        "$OUT/mem-$suf.o" "$OUT/str-$suf.o"
}

qbase="-display none -monitor none -serial none -semihosting-config enable=on,target=native"

build_m m0 thumbv6m-none-eabi cortex-m0 \
    "$SRC/Cortex-M0/mem.S" "$SRC/Cortex-M0/string.S" "$A32/m_microbit.ld" ""
run_guest m0 "$OUT/m0.elf" $QEMU -M microbit $qbase -kernel "$OUT/m0.elf"

build_m m3 thumbv7m-none-eabi cortex-m3 \
    "$SRC/Cortex-M3/mem.S" "$SRC/Cortex-M3/string.S" "$A32/m_mps2.ld" ""
run_guest m3 "$OUT/m3.elf" $QEMU -M mps2-an385 $qbase -kernel "$OUT/m3.elf"

build_m m4 thumbv7em-none-eabi cortex-m4 \
    "$SRC/Cortex-M4/mem.S" "$SRC/Cortex-M4/string.S" "$A32/m_mps2.ld" "-mfpu=none"
run_guest m4 "$OUT/m4.elf" $QEMU -M mps2-an386 $qbase -kernel "$OUT/m4.elf"

build_m m7 thumbv7em-none-eabi cortex-m7 \
    "$SRC/Cortex-M7/mem.S" "$SRC/Cortex-M7/string.S" "$A32/m_mps2.ld" "-mfpu=none"
run_guest m7 "$OUT/m7.elf" $QEMU -M mps2-an500 $qbase -kernel "$OUT/m7.elf"

build_m m33 thumbv8m.main-none-eabi cortex-m33 \
    "$SRC/Cortex-M33/mem.S" "$SRC/Cortex-M33/string.S" "$A32/m_an505.ld" ""
run_guest m33 "$OUT/m33.elf" $QEMU -M mps2-an505 $qbase -kernel "$OUT/m33.elf"

build_m m55 thumbv8.1m.main-none-eabi cortex-m55 \
    "$SRC/Cortex-M55/mem.S" "$SRC/Cortex-M55/string.S" "$A32/m_an547.ld" "-DRT_CPACR"
run_guest m55 "$OUT/m55.elf" $QEMU -M mps3-an547 $qbase -kernel "$OUT/m55.elf"

build_a a32 armv7-none-eabi cortex-a7 neon-vfpv4 \
    "$SRC/NEON/mem.S" "$SRC/NEON/string.S" "$A32/a_virt.ld"
run_guest a32-a7 "$OUT/a32.elf" $QEMU -M virt -cpu cortex-a7 -m 128 $qbase -kernel "$OUT/a32.elf"
run_guest a32-a15 "$OUT/a32.elf" $QEMU -M virt -cpu cortex-a15 -m 128 $qbase -kernel "$OUT/a32.elf"

build_a arm1176 armv6-none-eabi arm1176jzf-s vfpv2 \
    "$SRC/ARM1176/mem.S" "$SRC/ARM1176/string.S" "$A32/a_raspi0.ld"
run_guest arm1176 "$OUT/arm1176.elf" $QEMU -M raspi0 \
    -display none -monitor none -serial stdio \
    -semihosting-config enable=on,target=native \
    -kernel "$OUT/arm1176.elf"

echo "aarch32: all guests fail 0"
