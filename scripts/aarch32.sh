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
# Guest times are QEMU ticks, not silicon, and do not go in bench.html.
# A stuck counter prints N/A. strscpy, strscat, strpad have no libc symbol.
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
    p = subprocess.run(cmd, timeout=180, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
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
    set -- "$OUT/start-$suf.o" "$OUT/bench-$suf.o" \
        "$OUT/mem-$suf.o" "$OUT/str-$suf.o"
    for o in "$OUT/libc-$suf"/*.o; do
        set -- "$@" "$o"
    done
    $LD -T "$ld" -o "$OUT/$suf.elf" "$@"
}

build_a() {
    suf=$1
    target=$2
    cpu=$3
    fpu=$4
    mem=$5
    str=$6
    ld=$7
    extra=$8
    neondef=
    clkdef=
    if [ "$suf" = a32 ]; then
        neondef=-DRT_NEON
        clkdef=-DRT_PMU
    fi
    if [ "$suf" = arm1176 ]; then
        clkdef=-DRT_PMU6
    fi
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm $CF \
        $clkdef $extra \
        -c -o "$OUT/bench-$suf.o" verify/suite/a32_bench.c -DRT_SUF="$suf"
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm \
        $neondef $clkdef $extra -c -o "$OUT/start-$suf.o" "$A32/a_start.S"
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm \
        -c -o "$OUT/mem-$suf.o" "$mem"
    $CLANG -target "$target" -mcpu="$cpu" -mfpu="$fpu" -mfloat-abi=soft -marm \
        -c -o "$OUT/str-$suf.o" "$str"
    set -- "$OUT/start-$suf.o" "$OUT/bench-$suf.o" \
        "$OUT/mem-$suf.o" "$OUT/str-$suf.o"
    for o in "$OUT/libc-$suf"/*.o; do
        set -- "$@" "$o"
    done
    $LD -T "$ld" -o "$OUT/$suf.elf" "$@"
}

EXT=$OUT/ext
mkdir -p "$EXT/inc" "$EXT/machine"
printf '/* clang supplies the architecture macros */\n' > "$EXT/inc/picolibc.h"
printf 'typedef unsigned int size_t;\n' > "$EXT/inc/string.h"
printf '/* unused */\n' > "$EXT/machine/acle-compat.h"
cat > "$EXT/unwind.S" << 'EOF'
.syntax unified
.global __aeabi_unwind_cpp_pr0
__aeabi_unwind_cpp_pr0:
    bx lr
EOF

fetch() {
    curl -fsSL -o "$1" "$2"
}

AOR=https://raw.githubusercontent.com/ARM-software/optimized-routines/v25.01/string/arm
PICO=https://raw.githubusercontent.com/picolibc/picolibc/1.8.10/newlib/libc/machine/arm
fetch "$EXT/asmdefs.h" "$AOR/asmdefs.h"
fetch "$EXT/memcpy.S" "$AOR/memcpy.S"
fetch "$EXT/memset.S" "$AOR/memset.S"
fetch "$EXT/strcmp.S" "$AOR/strcmp.S"
fetch "$EXT/strlen.S" "$AOR/strlen-armv6t2.S"
fetch "$EXT/arm_asm.h" "$PICO/arm_asm.h"
fetch "$EXT/memcpy-m.S" "$PICO/memcpy-armv7m.S"
fetch "$EXT/memset-t2.S" "$PICO/memset-thumb2.S"
fetch "$EXT/memset-t1.S" "$PICO/memset-thumb.S"
fetch "$EXT/strlen-t2.S" "$PICO/strlen-thumb2-Os.S"
fetch "$EXT/strlen-t1.S" "$PICO/strlen-thumb1-Os.S"
fetch "$EXT/strnlen.c" \
    https://raw.githubusercontent.com/picolibc/picolibc/1.8.10/newlib/libc/string/strnlen.c \
    || true

veneer() {
    mode=$1
    dst=$2
    src=$3
    if [ "$mode" = thumb ]; then
        cat >> "$libc_dir/alias.S" << EOF
.thumb
.thumb_func
.global $dst
$dst:
    push {lr}
    bl $src
    pop {pc}
EOF
    else
        cat >> "$libc_dir/alias.S" << EOF
.arm
.global $dst
$dst:
    push {lr}
    bl $src
    pop {pc}
EOF
    fi
}

begin_libc() {
    libc_dir=$OUT/libc-$1
    mkdir -p "$libc_dir"
    printf '.syntax unified\n' > "$libc_dir/alias.S"
    libc_defs=
}

end_libc() {
    suf=$1
    target=$2
    cpu=$3
    cmode=$4
    fpu=$5
    isa=$6
    $CLANG -target "$target" -mcpu="$cpu" $cmode $fpu \
        -c -o "$libc_dir/unwind.o" "$EXT/unwind.S"
    $CLANG -target "$target" -mcpu="$cpu" $cmode $fpu \
        -c -o "$libc_dir/alias.o" "$libc_dir/alias.S"
    if [ -f "$EXT/strnlen.c" ]; then
        if $CLANG -target "$target" -mcpu="$cpu" $cmode $fpu $CF -nostdinc \
            -I"$EXT/inc" -c -o "$libc_dir/strnlen.o" "$EXT/strnlen.c"; then
            libc_defs="$libc_defs -DRT_LIBC_STRNLEN"
            veneer "$isa" libc_strnlen strnlen
            $CLANG -target "$target" -mcpu="$cpu" $cmode $fpu \
                -c -o "$libc_dir/alias.o" "$libc_dir/alias.S"
        else
            rm -f "$libc_dir/strnlen.o"
        fi
    fi
}

pico_thumb2() {
    suf=$1
    target=$2
    cpu=$3
    fpu=$4
    begin_libc "$suf"
    veneer thumb libc_memcpy memcpy
    veneer thumb libc_memset memset
    veneer thumb libc_strlen strlen
    end_libc "$suf" "$target" "$cpu" -mthumb "$fpu" thumb
    $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
        -I"$EXT" -I"$EXT/inc" \
        -c -o "$OUT/libc-$suf/memcpy.o" "$EXT/memcpy-m.S"
    $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
        -I"$EXT" -I"$EXT/inc" \
        -c -o "$OUT/libc-$suf/memset.o" "$EXT/memset-t2.S"
    $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
        -I"$EXT" -I"$EXT/inc" \
        -c -o "$OUT/libc-$suf/strlen.o" "$EXT/strlen-t2.S"
}

qbase="-display none -monitor none -serial none -semihosting-config enable=on,target=native"

begin_libc m0
veneer thumb libc_memset memset
veneer thumb libc_strlen strlen
end_libc m0 thumbv6m-none-eabi cortex-m0 -mthumb "" thumb
$CLANG -target thumbv6m-none-eabi -mcpu=cortex-m0 -mthumb \
    -I"$EXT" -I"$EXT/inc" -c -o "$OUT/libc-m0/memset.o" "$EXT/memset-t1.S"
$CLANG -target thumbv6m-none-eabi -mcpu=cortex-m0 -mthumb \
    -I"$EXT" -I"$EXT/inc" -c -o "$OUT/libc-m0/strlen.o" "$EXT/strlen-t1.S"
build_m m0 thumbv6m-none-eabi cortex-m0 \
    "$SRC/Cortex-M0/mem.S" "$SRC/Cortex-M0/string.S" "$A32/m_microbit.ld" \
    "-DRT_LIBC_MEMSET -DRT_LIBC_STRLEN $libc_defs"
run_guest m0 "$OUT/m0.elf" $QEMU -M microbit $qbase -kernel "$OUT/m0.elf"

pico_thumb2 m3 thumbv7m-none-eabi cortex-m3 ""
build_m m3 thumbv7m-none-eabi cortex-m3 \
    "$SRC/Cortex-M3/mem.S" "$SRC/Cortex-M3/string.S" "$A32/m_mps2.ld" \
    "-DRT_DWT -DRT_LIBC_MEMCPY -DRT_LIBC_MEMSET -DRT_LIBC_STRLEN $libc_defs"
run_guest m3 "$OUT/m3.elf" $QEMU -M mps2-an385 $qbase -kernel "$OUT/m3.elf"

pico_thumb2 m4 thumbv7em-none-eabi cortex-m4 "-mfpu=none"
build_m m4 thumbv7em-none-eabi cortex-m4 \
    "$SRC/Cortex-M4/mem.S" "$SRC/Cortex-M4/string.S" "$A32/m_mps2.ld" \
    "-mfpu=none -DRT_DWT -DRT_LIBC_MEMCPY -DRT_LIBC_MEMSET -DRT_LIBC_STRLEN $libc_defs"
run_guest m4 "$OUT/m4.elf" $QEMU -M mps2-an386 $qbase -kernel "$OUT/m4.elf"

pico_thumb2 m7 thumbv7em-none-eabi cortex-m7 "-mfpu=none"
build_m m7 thumbv7em-none-eabi cortex-m7 \
    "$SRC/Cortex-M7/mem.S" "$SRC/Cortex-M7/string.S" "$A32/m_mps2.ld" \
    "-mfpu=none -DRT_DWT -DRT_LIBC_MEMCPY -DRT_LIBC_MEMSET -DRT_LIBC_STRLEN $libc_defs"
run_guest m7 "$OUT/m7.elf" $QEMU -M mps2-an500 $qbase -kernel "$OUT/m7.elf"

pico_thumb2 m33 thumbv8m.main-none-eabi cortex-m33 ""
build_m m33 thumbv8m.main-none-eabi cortex-m33 \
    "$SRC/Cortex-M33/mem.S" "$SRC/Cortex-M33/string.S" "$A32/m_an505.ld" \
    "-DRT_DWT -DRT_LIBC_MEMCPY -DRT_LIBC_MEMSET -DRT_LIBC_STRLEN $libc_defs"
run_guest m33 "$OUT/m33.elf" $QEMU -M mps2-an505 $qbase -kernel "$OUT/m33.elf"

begin_libc m55
end_libc m55 thumbv8.1m.main-none-eabi cortex-m55 -mthumb "" thumb
build_m m55 thumbv8.1m.main-none-eabi cortex-m55 \
    "$SRC/Cortex-M55/mem.S" "$SRC/Cortex-M55/string.S" "$A32/m_an547.ld" \
    "-DRT_DWT -DRT_CPACR $libc_defs"
run_guest m55 "$OUT/m55.elf" $QEMU -M mps3-an547 $qbase -kernel "$OUT/m55.elf"

begin_libc a32
veneer arm libc_memcpy __memcpy_arm
veneer thumb libc_memset __memset_arm
veneer thumb libc_strcmp __strcmp_arm
veneer thumb libc_strlen __strlen_armv6t2
end_libc a32 armv7-none-eabi cortex-a7 -marm "-mfpu=neon-vfpv4 -mfloat-abi=soft" arm
$CLANG -target armv7-none-eabi -mcpu=cortex-a7 -marm \
    -mfpu=neon-vfpv4 -mfloat-abi=soft -D__ARM_NEON__=1 -I"$EXT" \
    -c -o "$OUT/libc-a32/memcpy.o" "$EXT/memcpy.S"
$CLANG -target armv7-none-eabi -mcpu=cortex-a7 -mthumb \
    -mfpu=neon-vfpv4 -mfloat-abi=soft -I"$EXT" \
    -c -o "$OUT/libc-a32/memset.o" "$EXT/memset.S"
$CLANG -target armv7-none-eabi -mcpu=cortex-a7 -mthumb \
    -mfpu=neon-vfpv4 -mfloat-abi=soft -I"$EXT" \
    -c -o "$OUT/libc-a32/strcmp.o" "$EXT/strcmp.S"
$CLANG -target armv7-none-eabi -mcpu=cortex-a7 -mthumb \
    -mfpu=neon-vfpv4 -mfloat-abi=soft -I"$EXT" \
    -c -o "$OUT/libc-a32/strlen.o" "$EXT/strlen.S"
build_a a32 armv7-none-eabi cortex-a7 neon-vfpv4 \
    "$SRC/NEON/mem.S" "$SRC/NEON/string.S" "$A32/a_virt.ld" \
    "-DRT_A_PROFILE -DRT_LIBC_MEMCPY -DRT_LIBC_MEMSET -DRT_LIBC_STRCMP -DRT_LIBC_STRLEN $libc_defs"
run_guest a32-a7 "$OUT/a32.elf" $QEMU -M virt -cpu cortex-a7 -m 128 $qbase -kernel "$OUT/a32.elf"
run_guest a32-a15 "$OUT/a32.elf" $QEMU -M virt -cpu cortex-a15 -m 128 $qbase -kernel "$OUT/a32.elf"

begin_libc arm1176
veneer arm libc_memcpy __memcpy_arm
end_libc arm1176 armv6-none-eabi arm1176jzf-s -marm "-mfpu=vfpv2 -mfloat-abi=soft" arm
$CLANG -target armv6-none-eabi -mcpu=arm1176jzf-s -marm \
    -mfpu=vfpv2 -mfloat-abi=soft -I"$EXT" \
    -c -o "$OUT/libc-arm1176/memcpy.o" "$EXT/memcpy.S"
build_a arm1176 armv6-none-eabi arm1176jzf-s vfpv2 \
    "$SRC/ARM1176/mem.S" "$SRC/ARM1176/string.S" "$A32/a_raspi0.ld" \
    "-DRT_A_PROFILE -DRT_LIBC_MEMCPY $libc_defs"
run_guest arm1176 "$OUT/arm1176.elf" $QEMU -M raspi0 \
    -display none -monitor none -serial stdio \
    -semihosting-config enable=on,target=native \
    -kernel "$OUT/arm1176.elf"

echo "aarch32: all guests fail 0"
