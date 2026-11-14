#!/bin/sh
# Linux armhf table for one AArch32 kernel.
# CLOCK_MONOTONIC and this board's libc. strscpy, strscat, and strpad
# stay N/A in the libc column. Pi 5 cannot run AArch32.
# HWCAP neon selects rt_*_a32. No NEON selects rt_*_arm1176.
# Any other machine typechecks the C and the armhf objects, and does not
# execute an armhf binary.
set -e
cd "$(dirname "$0")/.."

OUT=build/aarch32-hw
rm -rf "$OUT"
mkdir -p "$OUT"

if [ -x /opt/homebrew/opt/llvm/bin/clang ]; then
    CLANG=/opt/homebrew/opt/llvm/bin/clang
elif command -v clang >/dev/null 2>&1; then
    CLANG=clang
else
    CLANG=gcc
fi

typecheck() {
    "$CLANG" -std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-builtin \
        -DRT_HOST -DRT_SUF=a32 \
        -c -o "$OUT/bench-host.o" verify/suite/a32_bench.c
}

cross_objects() {
    "$CLANG" --target=armv7-linux-gnueabihf -mcpu=cortex-a7 -mfpu=neon \
        -mfloat-abi=hard -marm \
        -c -o "$OUT/mem-a32.o" src/aarch32/NEON/mem.S
    "$CLANG" --target=armv7-linux-gnueabihf -mcpu=cortex-a7 -mfpu=neon \
        -mfloat-abi=hard -marm \
        -c -o "$OUT/str-a32.o" src/aarch32/NEON/string.S
    "$CLANG" --target=armv6-linux-gnueabihf -mcpu=arm1176jzf-s \
        -mfloat-abi=hard -marm \
        -c -o "$OUT/mem-arm1176.o" src/aarch32/ARM1176/mem.S
    "$CLANG" --target=armv6-linux-gnueabihf -mcpu=arm1176jzf-s \
        -mfloat-abi=hard -marm \
        -c -o "$OUT/str-arm1176.o" src/aarch32/ARM1176/string.S
    echo "aarch32-hw: armhf objects ok"
}

arch=$(uname -m)
case "$arch" in
armv6l|armv7l) ;;
*)
    typecheck
    cross_objects
    echo "aarch32-hw: $(uname -m) does not run the armhf binary"
    exit 0
    ;;
esac

neon=0
if grep -q ' neon' /proc/cpuinfo 2>/dev/null; then
    neon=1
fi

CF="-std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-builtin -mfloat-abi=hard"

if [ "$neon" -eq 1 ]; then
    suf=a32
    "$CLANG" $CF -DRT_HOST -DRT_A_PROFILE -DRT_SUF=a32 \
        -mfpu=neon -mcpu=cortex-a7 \
        -c -o "$OUT/bench.o" verify/suite/a32_bench.c
    "$CLANG" -mcpu=cortex-a7 -mfpu=neon -mfloat-abi=hard -marm \
        -c -o "$OUT/mem.o" src/aarch32/NEON/mem.S
    "$CLANG" -mcpu=cortex-a7 -mfpu=neon -mfloat-abi=hard -marm \
        -c -o "$OUT/str.o" src/aarch32/NEON/string.S
else
    suf=arm1176
    "$CLANG" $CF -DRT_HOST -DRT_A_PROFILE -DRT_SUF=arm1176 \
        -mcpu=arm1176jzf-s -marm \
        -c -o "$OUT/bench.o" verify/suite/a32_bench.c
    "$CLANG" -mcpu=arm1176jzf-s -mfloat-abi=hard -marm \
        -c -o "$OUT/mem.o" src/aarch32/ARM1176/mem.S
    "$CLANG" -mcpu=arm1176jzf-s -mfloat-abi=hard -marm \
        -c -o "$OUT/str.o" src/aarch32/ARM1176/string.S
fi

"$CLANG" -mfloat-abi=hard -o "$OUT/$suf" "$OUT/bench.o" "$OUT/mem.o" "$OUT/str.o"
echo "aarch32-hw: $suf neon=$neon"
"$OUT/$suf"
