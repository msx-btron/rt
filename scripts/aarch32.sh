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
# QEMU has no DWT CYCCNT. Those guests time with semihost SYS_ELAPSED
# and label the columns host microseconds. A-profile virt keeps the PMU.
# strscpy, strscat, strpad have no libc symbol.
# Baselines are third_party/aarch32. Each table prints the source URL.
# A32_LIBC selects one tree. Unset prints picolibc and AOR, then the
# other imported memcpy bodies (visenri, LLVM, NuttX) on the guests
# that can run them. A32_ONLY=m3 runs one guest and skips that tail.
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
    p = subprocess.run(cmd, timeout=300, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
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

TP=third_party/aarch32
PICO=$TP/picolibc
AORD=$TP/aor
NUTTX=$TP/nuttx/arch_memcpy.S
VIS=$TP/visenri
LLVM=$TP/llvm-libc
PICO_BLOB=https://github.com/picolibc/picolibc/blob/1.8.10
AOR_BLOB=https://github.com/ARM-software/optimized-routines/blob/v25.01/string/arm
NUTTX_URL=https://github.com/NuttX/nuttx/blob/6b31918b429e6b2351bfa03f005704d123cb70e9/libs/libc/machine/arm/armv7-m/gnu/arch_memcpy.S
VIS_URL=https://github.com/visenri/memcpy_armv6m/blob/2dc57cc1d5944f181db11a0491dba5a00f7c350f/memops_opt/memcpy_armv6m.S
LLVM_URL=https://github.com/llvm/llvm-project/blob/a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0/libc/src/string/memory_utils/arm/inline_memcpy.h
STRNLEN_URL=$PICO_BLOB/newlib/libc/string/strnlen.c
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

set_mode() {
    A32_LIBC=$1
    case "$A32_LIBC" in
    default) use_pico=1; use_aor=1; bdef= ;;
    pico) use_pico=1; use_aor=0; bdef='-DRT_BASELINE="picolibc-1.8.10"' ;;
    aor) use_pico=0; use_aor=1; bdef='-DRT_BASELINE="Arm-Optimized-Routines-v25.01"' ;;
    visenri) use_pico=0; use_aor=0; bdef='-DRT_BASELINE="visenri-memcpy_armv6m-2dc57cc"' ;;
    llvm-m0) use_pico=0; use_aor=0; bdef='-DRT_BASELINE="LLVM-libc-low-end-a080750"' ;;
    llvm-mid) use_pico=0; use_aor=0; bdef='-DRT_BASELINE="LLVM-libc-mid-end-a080750"' ;;
    nuttx) use_pico=0; use_aor=0; bdef='-DRT_BASELINE="NuttX-arch_memcpy.S-6b31918"' ;;
    *)
        echo "aarch32: A32_LIBC must be pico, aor, visenri, llvm-m0, llvm-mid, or nuttx"
        exit 1
        ;;
    esac
}

set_mode "${A32_LIBC:-default}"

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
    rm -rf "$libc_dir"
    mkdir -p "$libc_dir"
    printf '.syntax unified\n' > "$libc_dir/alias.S"
    libc_defs=
}

add_src() {
    srcdef="$srcdef -D$1=\"$2\""
}

only_guest() {
    if [ -z "$A32_ONLY" ]; then
        return 0
    fi
    if [ "$A32_ONLY" = "$1" ]; then
        return 0
    fi
    return 1
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
    if [ "$use_pico" = 1 ] && [ -f "$PICO/strnlen.c" ]; then
        if $CLANG -target "$target" -mcpu="$cpu" $cmode $fpu $CF -nostdinc \
            -I"$EXT/inc" -c -o "$libc_dir/strnlen.o" "$PICO/strnlen.c"; then
            libc_defs="$libc_defs -DRT_LIBC_STRNLEN"
            add_src RT_SRC_STRNLEN "$STRNLEN_URL"
            veneer "$isa" libc_strnlen strnlen
            $CLANG -target "$target" -mcpu="$cpu" $cmode $fpu \
                -c -o "$libc_dir/alias.o" "$libc_dir/alias.S"
        else
            rm -f "$libc_dir/strnlen.o"
        fi
    fi
}

compile_strcmp() {
    suf=$1
    target=$2
    cpu=$3
    fpu=$4
    $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu -U__ARM_FEATURE_SIMD32 \
        -I"$PICO" -I"$EXT" -I"$EXT/inc" \
        -c -o "$OUT/libc-$suf/strcmp.o" "$PICO/strcmp.S"
}

pico_thumb2() {
    suf=$1
    target=$2
    cpu=$3
    fpu=$4
    begin_libc "$suf"
    guest_defs=
    if [ "$use_pico" = 1 ]; then
        veneer thumb libc_memcpy memcpy
        veneer thumb libc_memset memset
        veneer thumb libc_strlen strlen
        guest_defs="-DRT_LIBC_MEMCPY -DRT_LIBC_MEMSET -DRT_LIBC_STRLEN -DRT_LIBC_STRCMP"
        veneer thumb libc_strcmp strcmp
    fi
    if [ "$A32_LIBC" = nuttx ] || [ "$A32_LIBC" = llvm-mid ]; then
        veneer thumb libc_memcpy memcpy
        guest_defs="-DRT_LIBC_MEMCPY"
    fi
    end_libc "$suf" "$target" "$cpu" -mthumb "$fpu" thumb
    guest_defs="$guest_defs $libc_defs"
    if [ "$use_pico" = 1 ]; then
        $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
            -I"$PICO" -I"$EXT" -I"$EXT/inc" \
            -c -o "$OUT/libc-$suf/memcpy.o" "$PICO/memcpy-armv7m.S"
        add_src RT_SRC_MEMCPY "$PICO_BLOB/newlib/libc/machine/arm/memcpy-armv7m.S"
        $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
            -I"$PICO" -I"$EXT" -I"$EXT/inc" \
            -c -o "$OUT/libc-$suf/memset.o" "$PICO/memset-thumb2.S"
        add_src RT_SRC_MEMSET "$PICO_BLOB/newlib/libc/machine/arm/memset-thumb2.S"
        $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
            -I"$PICO" -I"$EXT" -I"$EXT/inc" \
            -c -o "$OUT/libc-$suf/strlen.o" "$PICO/strlen-thumb2-Os.S"
        add_src RT_SRC_STRLEN "$PICO_BLOB/newlib/libc/machine/arm/strlen-thumb2-Os.S"
        compile_strcmp "$suf" "$target" "$cpu" "$fpu"
        add_src RT_SRC_STRCMP "$PICO_BLOB/newlib/libc/machine/arm/strcmp.S"
    fi
    if [ "$A32_LIBC" = nuttx ]; then
        $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
            -c -o "$OUT/libc-$suf/memcpy.o" "$NUTTX"
        add_src RT_SRC_MEMCPY "$NUTTX_URL"
    fi
    if [ "$A32_LIBC" = llvm-mid ]; then
        src=$LLVM/memcpy-mid.S
        if [ "$cpu" = cortex-m7 ]; then
            src=$LLVM/memcpy-m7.S
        fi
        $CLANG -target "$target" -mcpu="$cpu" -mthumb $fpu \
            -c -o "$OUT/libc-$suf/memcpy.o" "$src"
        add_src RT_SRC_MEMCPY "$LLVM_URL"
    fi
}

gas_visenri() {
    gas=
    if [ -x /opt/homebrew/bin/arm-linux-musleabihf-as ]; then
        gas=/opt/homebrew/bin/arm-linux-musleabihf-as
    elif command -v arm-linux-musleabihf-as >/dev/null 2>&1; then
        gas=arm-linux-musleabihf-as
    elif command -v arm-linux-gnueabihf-as >/dev/null 2>&1; then
        gas=arm-linux-gnueabihf-as
    elif command -v arm-none-eabi-as >/dev/null 2>&1; then
        gas=arm-none-eabi-as
    else
        echo "aarch32: visenri needs GNU as; clang rejects LOCAL"
        exit 1
    fi
    $CLANG -E -x assembler-with-cpp -target thumbv6m-none-eabi \
        -mcpu=cortex-m0 -mthumb -I"$VIS" \
        "$VIS/memcpy_armv6m.S" -o "$OUT/visenri.s"
    $gas -mcpu=cortex-m0 -mthumb -o "$OUT/libc-m0/memcpy.o" "$OUT/visenri.s"
}

qbase="-display none -monitor none -serial none -semihosting-config enable=on,target=native"

run_modes() {
    if only_guest m0; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/Cortex-M0/"
        begin_libc m0
        guest_defs=
        if [ "$use_pico" = 1 ]; then
            veneer thumb libc_memset memset
            veneer thumb libc_strlen strlen
            veneer thumb libc_strcmp strcmp
            guest_defs="-DRT_LIBC_MEMSET -DRT_LIBC_STRLEN -DRT_LIBC_STRCMP"
        fi
        if [ "$A32_LIBC" = visenri ] || [ "$A32_LIBC" = llvm-m0 ]; then
            if [ "$A32_LIBC" = visenri ]; then
                veneer thumb libc_memcpy memcpy_armv6m
            else
                veneer thumb libc_memcpy memcpy
            fi
            guest_defs="-DRT_LIBC_MEMCPY"
        fi
        end_libc m0 thumbv6m-none-eabi cortex-m0 -mthumb "" thumb
        guest_defs="$guest_defs $libc_defs"
        if [ "$use_pico" = 1 ]; then
            $CLANG -target thumbv6m-none-eabi -mcpu=cortex-m0 -mthumb \
                -I"$PICO" -I"$EXT" -I"$EXT/inc" \
                -c -o "$OUT/libc-m0/memset.o" "$PICO/memset-thumb.S"
            add_src RT_SRC_MEMSET "$PICO_BLOB/newlib/libc/machine/arm/memset-thumb.S"
            $CLANG -target thumbv6m-none-eabi -mcpu=cortex-m0 -mthumb \
                -I"$PICO" -I"$EXT" -I"$EXT/inc" \
                -c -o "$OUT/libc-m0/strlen.o" "$PICO/strlen-thumb1-Os.S"
            add_src RT_SRC_STRLEN "$PICO_BLOB/newlib/libc/machine/arm/strlen-thumb1-Os.S"
            compile_strcmp m0 thumbv6m-none-eabi cortex-m0 ""
            add_src RT_SRC_STRCMP "$PICO_BLOB/newlib/libc/machine/arm/strcmp.S"
        fi
        if [ "$A32_LIBC" = visenri ]; then
            gas_visenri
            add_src RT_SRC_MEMCPY "$VIS_URL"
        fi
        if [ "$A32_LIBC" = llvm-m0 ]; then
            $CLANG -target thumbv6m-none-eabi -mcpu=cortex-m0 -mthumb \
                -c -o "$OUT/libc-m0/memcpy.o" "$LLVM/memcpy-m0.S"
            add_src RT_SRC_MEMCPY "$LLVM_URL"
        fi
        build_m m0 thumbv6m-none-eabi cortex-m0 \
            "$SRC/Cortex-M0/mem.S" "$SRC/Cortex-M0/string.S" "$A32/m_microbit.ld" \
            "$guest_defs $bdef $srcdef"
        run_guest m0 "$OUT/m0.elf" $QEMU -M microbit $qbase -kernel "$OUT/m0.elf"
    fi

    if only_guest m3; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/Cortex-M3/"
        pico_thumb2 m3 thumbv7m-none-eabi cortex-m3 ""
        build_m m3 thumbv7m-none-eabi cortex-m3 \
            "$SRC/Cortex-M3/mem.S" "$SRC/Cortex-M3/string.S" "$A32/m_mps2.ld" \
            "-DRT_DWT $guest_defs $bdef $srcdef"
        run_guest m3 "$OUT/m3.elf" $QEMU -M mps2-an385 $qbase -kernel "$OUT/m3.elf"
    fi

    if only_guest m4; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/Cortex-M4/"
        pico_thumb2 m4 thumbv7em-none-eabi cortex-m4 "-mfpu=none"
        build_m m4 thumbv7em-none-eabi cortex-m4 \
            "$SRC/Cortex-M4/mem.S" "$SRC/Cortex-M4/string.S" "$A32/m_mps2.ld" \
            "-mfpu=none -DRT_DWT $guest_defs $bdef $srcdef"
        run_guest m4 "$OUT/m4.elf" $QEMU -M mps2-an386 $qbase -kernel "$OUT/m4.elf"
    fi

    if only_guest m7; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/Cortex-M7/"
        pico_thumb2 m7 thumbv7em-none-eabi cortex-m7 "-mfpu=none"
        build_m m7 thumbv7em-none-eabi cortex-m7 \
            "$SRC/Cortex-M7/mem.S" "$SRC/Cortex-M7/string.S" "$A32/m_mps2.ld" \
            "-mfpu=none -DRT_DWT $guest_defs $bdef $srcdef"
        run_guest m7 "$OUT/m7.elf" $QEMU -M mps2-an500 $qbase -kernel "$OUT/m7.elf"
    fi

    if only_guest m33; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/Cortex-M33/"
        pico_thumb2 m33 thumbv8m.main-none-eabi cortex-m33 ""
        build_m m33 thumbv8m.main-none-eabi cortex-m33 \
            "$SRC/Cortex-M33/mem.S" "$SRC/Cortex-M33/string.S" "$A32/m_an505.ld" \
            "-DRT_DWT $guest_defs $bdef $srcdef"
        run_guest m33 "$OUT/m33.elf" $QEMU -M mps2-an505 $qbase -kernel "$OUT/m33.elf"
    fi

    if only_guest m55; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/Cortex-M55/"
        begin_libc m55
        end_libc m55 thumbv8.1m.main-none-eabi cortex-m55 -mthumb "" thumb
        build_m m55 thumbv8.1m.main-none-eabi cortex-m55 \
            "$SRC/Cortex-M55/mem.S" "$SRC/Cortex-M55/string.S" "$A32/m_an547.ld" \
            "-DRT_DWT -DRT_CPACR $libc_defs $bdef $srcdef"
        run_guest m55 "$OUT/m55.elf" $QEMU -M mps3-an547 $qbase -kernel "$OUT/m55.elf"
    fi

    if only_guest a32 || only_guest a32-a7 || only_guest a32-a15; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/NEON/"
        begin_libc a32
        a32_defs=
        if [ "$use_aor" = 1 ]; then
            veneer arm libc_memcpy __memcpy_arm
            veneer thumb libc_memset __memset_arm
            veneer thumb libc_strcmp __strcmp_arm
            veneer thumb libc_strlen __strlen_armv6t2
            a32_defs="-DRT_LIBC_MEMCPY -DRT_LIBC_MEMSET -DRT_LIBC_STRCMP -DRT_LIBC_STRLEN"
        fi
        end_libc a32 armv7-none-eabi cortex-a7 -marm "-mfpu=neon-vfpv4 -mfloat-abi=soft" arm
        a32_defs="$a32_defs $libc_defs"
        if [ "$use_aor" = 1 ]; then
            $CLANG -target armv7-none-eabi -mcpu=cortex-a7 -marm \
                -mfpu=neon-vfpv4 -mfloat-abi=soft -D__ARM_NEON__=1 -I"$AORD" \
                -c -o "$OUT/libc-a32/memcpy.o" "$AORD/memcpy.S"
            add_src RT_SRC_MEMCPY "$AOR_BLOB/memcpy.S"
            $CLANG -target armv7-none-eabi -mcpu=cortex-a7 -mthumb \
                -mfpu=neon-vfpv4 -mfloat-abi=soft -I"$AORD" \
                -c -o "$OUT/libc-a32/memset.o" "$AORD/memset.S"
            add_src RT_SRC_MEMSET "$AOR_BLOB/memset.S"
            $CLANG -target armv7-none-eabi -mcpu=cortex-a7 -mthumb \
                -mfpu=neon-vfpv4 -mfloat-abi=soft -I"$AORD" \
                -c -o "$OUT/libc-a32/strcmp.o" "$AORD/strcmp.S"
            add_src RT_SRC_STRCMP "$AOR_BLOB/strcmp.S"
            $CLANG -target armv7-none-eabi -mcpu=cortex-a7 -mthumb \
                -mfpu=neon-vfpv4 -mfloat-abi=soft -I"$AORD" \
                -c -o "$OUT/libc-a32/strlen.o" "$AORD/strlen-armv6t2.S"
            add_src RT_SRC_STRLEN "$AOR_BLOB/strlen-armv6t2.S"
        fi
        build_a a32 armv7-none-eabi cortex-a7 neon-vfpv4 \
            "$SRC/NEON/mem.S" "$SRC/NEON/string.S" "$A32/a_virt.ld" \
            "-DRT_A_PROFILE $a32_defs $bdef $srcdef"
        if only_guest a32 || only_guest a32-a7; then
            run_guest a32-a7 "$OUT/a32.elf" $QEMU -M virt -cpu cortex-a7 -m 128 $qbase -kernel "$OUT/a32.elf"
        fi
        if only_guest a32 || only_guest a32-a15; then
            run_guest a32-a15 "$OUT/a32.elf" $QEMU -M virt -cpu cortex-a15 -m 128 $qbase -kernel "$OUT/a32.elf"
        fi
    fi

    if only_guest arm1176; then
        srcdef=
        add_src RT_KERNEL "src/aarch32/ARM1176/"
        begin_libc arm1176
        a6_defs=
        if [ "$use_aor" = 1 ]; then
            veneer arm libc_memcpy __memcpy_arm
            a6_defs="-DRT_LIBC_MEMCPY"
        fi
        end_libc arm1176 armv6-none-eabi arm1176jzf-s -marm "-mfpu=vfpv2 -mfloat-abi=soft" arm
        a6_defs="$a6_defs $libc_defs"
        if [ "$use_aor" = 1 ]; then
            $CLANG -target armv6-none-eabi -mcpu=arm1176jzf-s -marm \
                -mfpu=vfpv2 -mfloat-abi=soft -I"$AORD" \
                -c -o "$OUT/libc-arm1176/memcpy.o" "$AORD/memcpy.S"
            add_src RT_SRC_MEMCPY "$AOR_BLOB/memcpy.S"
        fi
        build_a arm1176 armv6-none-eabi arm1176jzf-s vfpv2 \
            "$SRC/ARM1176/mem.S" "$SRC/ARM1176/string.S" "$A32/a_raspi0.ld" \
            "-DRT_A_PROFILE $a6_defs $bdef $srcdef"
        run_guest arm1176 "$OUT/arm1176.elf" $QEMU -M raspi0 \
            -display none -monitor none -serial stdio \
            -semihosting-config enable=on,target=native \
            -kernel "$OUT/arm1176.elf"
    fi
}

run_modes

if [ "$A32_LIBC" = default ] && [ -z "$A32_ONLY" ]; then
    set_mode visenri
    A32_ONLY=m0
    run_modes
    set_mode llvm-m0
    A32_ONLY=m0
    run_modes
    set_mode nuttx
    for extra in m3 m4 m7 m33; do
        A32_ONLY=$extra
        run_modes
    done
    set_mode llvm-mid
    for extra in m3 m4 m7 m33; do
        A32_ONLY=$extra
        run_modes
    done
    A32_ONLY=
    set_mode default
fi

echo "aarch32: all guests fail 0"
