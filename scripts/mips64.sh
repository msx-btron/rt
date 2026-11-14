#!/bin/sh
# PlayStation 2 and Nintendo 64 kernel check.
#   auto (make mips): PCSX2 for the Emotion Engine tiers, and
#     qemu-system-mips64el -M malta -cpu R4000 for the VR4300 tiers.
#   ee:  assemble src/mips64/ee. PCSX2 is the EE runtime. This QEMU
#     has no R5900 on the 11.0.3 line.
#   rcp: scalar C99 (vectorizers off), scalar C99 (vectorizers on),
#     and the handwritten VR4300 kernels, on Malta.
# PCSX2 Count and Malta CP0 Count are emulator clocks. They do not
# belong in bench.html. Ares is not the runner.
# PCSX2 boots OpenPS2BIOS 0.6 (MIT, emulator only). The image is
# downloaded and checked. It is not a Sony ROM and it is not flashed.
set -eu
cd "$(dirname "$0")/.."

mode=${1:-auto}
case "$mode" in
auto|ee|rcp) ;;
*)
    echo "mips: usage: scripts/mips64.sh [auto|ee|rcp]" >&2
    exit 1
    ;;
esac

mkdir -p build/mips
OBJ=build/mips

have() {
    command -v "$1" >/dev/null 2>&1 || [ -x "$1" ]
}

CLANG=""
for c in ${CC_MIPS:-} /opt/homebrew/opt/llvm/bin/clang clang; do
    if [ -n "$c" ] && have "$c"; then
        if printf 'int x;\n' | "$c" -target mipsel-unknown-elf -march=mips64 \
            -mabi=32 -c -x c - -o "$OBJ/probe.o" >/dev/null 2>&1; then
            CLANG=$c
            break
        fi
    fi
done
rm -f "$OBJ/probe.o"

GCC=""
for c in ${CC_MIPS64EL:-} mips64el-linux-gnuabi64-gcc \
    mips64el-linux-gnuabi64-gcc-14 mips64el-linux-gnuabi64-gcc-13; do
    if [ -n "$c" ] && have "$c"; then
        GCC=$c
        break
    fi
done

LD=""
for c in ${LD_MIPS:-} mipsel-linux-gnu-ld /opt/homebrew/bin/mipsel-linux-gnu-ld; do
    if [ -n "$c" ] && have "$c"; then
        LD=$c
        break
    fi
done

NM=""
for c in llvm-nm /opt/homebrew/opt/llvm/bin/llvm-nm nm; do
    if [ -n "$c" ] && have "$c"; then
        NM=$c
        break
    fi
done

need_sym() {
    if ! "$NM" "$1" | grep -w "$2" >/dev/null; then
        echo "mips: $1 missing $2" >&2
        exit 1
    fi
}

as_o32() {
    out=$1
    inc=$2
    src=$3
    "$CLANG" -target mipsel-unknown-elf -march=mips64 -mabi=32 -msoft-float \
        -c -o "$out" -Wa,-I,"$inc" -Wa,-defsym,RT_MIPS_ILP32=1 "$src"
}

as_n64() {
    out=$1
    inc=$2
    src=$3
    if [ -n "$CLANG" ]; then
        "$CLANG" -target mips64el-unknown-elf -march=mips64 -mabi=64 \
            -msoft-float -mno-abicalls \
            -c -o "$out" -Wa,-I,"$inc" "$src"
    else
        "$GCC" -march=mips64 -mabi=64 -msoft-float -mno-abicalls \
            -c -o "$out" -Wa,-I,"$inc" "$src"
    fi
}

# o32 objects are the PCSX2 ELF. n64 objects are the Malta ELF.
# EE n64 is only the assemble-check (mode ee). Clang's n64 names turn
# O32 t0 and t4 into the same GPR, and that assemble is not what PCSX2 runs.
assemble_pair() {
    kind=$1
    want_n64=$2
    if [ -n "$CLANG" ]; then
        as_o32 "$OBJ/${kind}-mem.o" "src/mips64/$kind" "src/mips64/$kind/mem.s"
        as_o32 "$OBJ/${kind}-string.o" "src/mips64/$kind" "src/mips64/$kind/string.s"
        need_sym "$OBJ/${kind}-mem.o" "rt_memcpy_$kind"
        need_sym "$OBJ/${kind}-mem.o" "rt_memset_$kind"
        need_sym "$OBJ/${kind}-mem.o" "rt_memcmp_$kind"
        need_sym "$OBJ/${kind}-string.o" "rt_strlen_$kind"
        need_sym "$OBJ/${kind}-string.o" "rt_strscpy_$kind"
        need_sym "$OBJ/${kind}-string.o" "rt_strpad_$kind"
        echo "mips: assembled $kind (o32)"
    fi
    if [ "$want_n64" = "n64" ]; then
        if [ -z "$CLANG" ] && [ -z "$GCC" ]; then
            echo "mips: no n64 assembler for $kind" >&2
            exit 1
        fi
        as_n64 "$OBJ/${kind}-mem-n64.o" "src/mips64/$kind" "src/mips64/$kind/mem.s"
        as_n64 "$OBJ/${kind}-string-n64.o" "src/mips64/$kind" "src/mips64/$kind/string.s"
        echo "mips: assembled $kind (n64)"
    fi
    if [ -z "$CLANG" ] && [ -z "$GCC" ]; then
        echo "mips: no clang with -target mipsel-unknown-elf and no mips64el cross gcc" >&2
        exit 1
    fi
}

if [ "$mode" = "auto" ] || [ "$mode" = "ee" ]; then
    if [ "$mode" = "ee" ]; then
        assemble_pair ee n64
    else
        assemble_pair ee o32
    fi
fi
if [ "$mode" = "auto" ] || [ "$mode" = "rcp" ]; then
    assemble_pair rcp n64
fi

if [ "$mode" = "ee" ]; then
    cpuhelp=""
    if have qemu-system-mips64el; then
        cpuhelp=$(qemu-system-mips64el -cpu help 2>&1 || true)
    fi
    if printf '%s\n' "$cpuhelp" | grep -q R5900; then
        echo "mips: this QEMU lists R5900. No freestanding system loader is wired."
        echo "mips: EE runtime on this machine is PCSX2. Assemble-check passed."
    else
        echo "mips: QEMU has no R5900 CPU. EE assemble-check passed."
    fi
    exit 0
fi

ran=0

elf_cflags="-target mipsel-unknown-elf -march=mips64 -mabi=32 -msoft-float -G0 -fno-pic -ffreestanding -fno-builtin -fno-stack-protector -std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -Iinclude"
elf_off="$elf_cflags -fno-vectorize -fno-slp-vectorize"
elf_on="$elf_cflags -fvectorize -fslp-vectorize"

link_elf() {
    out=$1
    shift
    "$LD" -EL -T verify/suite/ps2.ld -o "$out" "$@"
}

LLD=""
if have ld.lld; then
    LLD=ld.lld
elif [ -x /opt/homebrew/bin/ld.lld ]; then
    LLD=/opt/homebrew/bin/ld.lld
fi

link_n64() {
    out=$1
    shift
    if [ -n "$LLD" ]; then
        "$LLD" -m elf64ltsmip -T verify/suite/malta.ld -o "$out" "$@"
    elif [ -n "$GCC" ]; then
        "$GCC" -nostdlib -static -march=mips64 -mabi=64 -msoft-float \
            -mno-abicalls -Wl,-T,verify/suite/malta.ld -o "$out" "$@"
    else
        echo "mips: no n64 linker (ld.lld or the mips64el cross gcc)" >&2
        exit 1
    fi
}

# Print guest table lines as the emulator writes them.
SEEN=0
drain_log() {
    log=$1
    n=$(tr -d '\r' < "$log" | wc -l | tr -d ' ')
    if [ "$n" -le "$SEEN" ]; then
        return
    fi
    tr -d '\r' < "$log" | awk -v seen="$SEEN" 'NR > seen { print }' |
        while IFS= read -r line; do
            case "$line" in
                *'| '*)
                    printf '%s\n' "$line" | sed 's/^[^|]*//'
                    ;;
                *binary:*|*checks:*|*'FAIL '*|*'] ticks'|ticks|*'] mem'|mem|*'] str'|str|*'run complete'*)
                    printf '%s\n' "$line" | sed 's/^\[[^]]*\] //'
                    ;;
            esac
        done || true
    SEEN=$n
}

wait_guest() {
    name=$1
    vm=$2
    log=$3
    limit=$4
    SEEN=0
    elapsed=0
    while kill -0 "$vm" 2>/dev/null; do
        drain_log "$log"
        if grep -q 'run complete' "$log"; then
            break
        fi
        if [ "$elapsed" -ge "$limit" ]; then
            echo "mips: $name timed out" >&2
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    kill -TERM "$vm" 2>/dev/null || true
    sleep 1
    kill -KILL "$vm" 2>/dev/null || true
    wait "$vm" 2>/dev/null || true
    drain_log "$log"
    tr -d '\r' < "$log" > "$OBJ/$name.txt"
    if ! grep -q 'run complete' "$OBJ/$name.txt"; then
        echo "mips: $name did not finish" >&2
        tail -30 "$OBJ/$name.txt" >&2
        if [ -s "$OBJ/$name.err" ]; then
            tail -30 "$OBJ/$name.err" >&2
        fi
        exit 1
    fi
    if ! grep -q 'fail: 0' "$OBJ/$name.txt"; then
        echo "mips: $name checks failed" >&2
        exit 1
    fi
}

# OpenPS2BIOS 0.6. Published checksum from the v0.6 release asset.
# Emulator use only. Do not flash this image onto a console.
OPENPS2_URL=https://github.com/TamaribaEmu/OpenPS2BIOS/releases/download/v0.6/OpenPS2BIOS-0.6.bin
OPENPS2_SHA=3702baa508ff40498fab4a95429a2ae1f903d11f5bbcdd4e1a87dbe9f5d21a84
OPENPS2_NAME=OpenPS2BIOS-0.6.bin

sha256_file() {
    if have sha256sum; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

fetch_openps2bios() {
    dest=$OBJ/$OPENPS2_NAME
    if [ -n "${PCSX2_BIOS:-}" ]; then
        dest=$PCSX2_BIOS
    fi
    if [ -f "$dest" ] && [ "$(sha256_file "$dest")" = "$OPENPS2_SHA" ]; then
        printf '%s\n' "$dest"
        return
    fi
    if [ -n "${PCSX2_BIOS:-}" ]; then
        echo "mips: PCSX2_BIOS is not OpenPS2BIOS 0.6" >&2
        exit 1
    fi
    if ! have curl; then
        echo "mips: curl is required to fetch OpenPS2BIOS" >&2
        exit 1
    fi
    part=$OBJ/$OPENPS2_NAME.partial
    curl -fsSL -o "$part" "$OPENPS2_URL"
    if [ "$(sha256_file "$part")" != "$OPENPS2_SHA" ]; then
        echo "mips: OpenPS2BIOS checksum mismatch" >&2
        rm -f "$part"
        exit 1
    fi
    mv "$part" "$dest"
    printf '%s\n' "$dest"
}

run_pcsx2() {
    name=$1
    elf=$2
    pcsx2=${PCSX2_BIN:-/Applications/PCSX2.app/Contents/MacOS/PCSX2}
    if [ ! -x "$pcsx2" ]; then
        echo "mips: PCSX2 not found at $pcsx2" >&2
        exit 1
    fi
    bios=$(fetch_openps2bios)
    real=$(cd "$(dirname "$elf")" && pwd -P)/$(basename "$elf")
    data=$(mktemp -d)
    log=$OBJ/$name.log
    mkdir -p "$data/PCSX2/bios" "$data/PCSX2/inis"
    cp "$bios" "$data/PCSX2/bios/$OPENPS2_NAME"
    cat > "$data/PCSX2/inis/PCSX2.ini" << 'EOF'
[UI]
SettingsVersion = 1
SetupWizardIncomplete = false

[Folders]
Bios = bios

[Filenames]
BIOS = OpenPS2BIOS-0.6.bin

[EmuCore]
EnableFastBoot = true
HostFs = false

[MemoryCards]
Slot1_Enable = false
Slot2_Enable = false

[Logging]
EnableSystemConsole = true
EnableTimestamps = true
EnableEEConsole = true
EnableIOPConsole = true
EOF
    : > "$log"
    echo "-------- PCSX2 $name OpenPS2BIOS 0.6 --------"
    "$pcsx2" -nogui -batch -fastboot -nofullscreen -earlyconsolelog \
        -logfile "$log" -datapath "$data" "$real" >/dev/null 2>"$OBJ/$name.err" &
    wait_guest "$name" "$!" "$log" 180
    rm -rf "$data"
}

run_malta() {
    name=$1
    elf=$2
    log=$OBJ/$name.log
    : > "$log"
    echo "-------- Malta R4000 $name --------"
    qemu-system-mips64el -M malta -cpu R4000 -m 64 -nographic \
        -display none -monitor none -serial stdio -kernel "$elf" >"$log" 2>&1 &
    wait_guest "$name" "$!" "$log" 300
}

if [ "$mode" = "auto" ] && [ -x "${PCSX2_BIN:-/Applications/PCSX2.app/Contents/MacOS/PCSX2}" ]; then
    if [ -z "$CLANG" ] || [ -z "$LD" ]; then
        echo "mips: PCSX2 is present but the o32 clang or mipsel linker is not" >&2
        exit 1
    fi
    echo "mips: PCSX2 Count is the emulator clock, not 294.912 MHz"
    "$CLANG" -target mipsel-unknown-elf -march=mips64 -mabi=32 -msoft-float \
        -c -o "$OBJ/start.o" verify/suite/ps2_start.s
    set -- $elf_off
    "$CLANG" "$@" -c -o "$OBJ/mem-off.o" src/common/scalar/mem.c
    "$CLANG" "$@" -c -o "$OBJ/string-off.o" src/common/scalar/string.c
    "$CLANG" "$@" -DRT_BINARY='"scalar-off"' -c -o "$OBJ/bench-off.o" verify/suite/ps2_bench.c
    set -- $elf_on
    "$CLANG" "$@" -DRT_VECTORIZE -c -o "$OBJ/mem-on.o" src/common/scalar/mem.c
    "$CLANG" "$@" -DRT_VECTORIZE -c -o "$OBJ/string-on.o" src/common/scalar/string.c
    "$CLANG" "$@" -DRT_VECTORIZE -DRT_BINARY='"scalar-on"' \
        -c -o "$OBJ/bench-on.o" verify/suite/ps2_bench.c
    set -- $elf_off
    "$CLANG" "$@" -DRT_WITH_EE -DRT_BINARY='"ee"' \
        -c -o "$OBJ/bench-ee.o" verify/suite/ps2_bench.c
    link_elf "$OBJ/scalar-off.elf" "$OBJ/start.o" "$OBJ/bench-off.o" \
        "$OBJ/mem-off.o" "$OBJ/string-off.o"
    link_elf "$OBJ/scalar-on.elf" "$OBJ/start.o" "$OBJ/bench-on.o" \
        "$OBJ/mem-on.o" "$OBJ/string-on.o"
    link_elf "$OBJ/ee.elf" "$OBJ/start.o" "$OBJ/bench-ee.o" \
        "$OBJ/mem-off.o" "$OBJ/string-off.o" \
        "$OBJ/ee-mem.o" "$OBJ/ee-string.o"
    run_pcsx2 scalar-off "$OBJ/scalar-off.elf"
    run_pcsx2 scalar-on "$OBJ/scalar-on.elf"
    run_pcsx2 ee "$OBJ/ee.elf"
    ran=1
fi

if [ "$mode" = "rcp" ] || [ "$mode" = "auto" ]; then
    if ! have qemu-system-mips64el; then
        if [ "$mode" = "rcp" ]; then
            echo "mips: qemu-system-mips64el not found" >&2
            exit 1
        fi
        echo "mips: qemu-system-mips64el is absent. VR4300 tables were not run."
    elif [ -z "$CLANG" ] && [ -z "$GCC" ]; then
        echo "mips: no compiler for the Malta ELF" >&2
        exit 1
    else
        if [ -n "$CLANG" ]; then
            CC_N64=$CLANG
            n64_off="-target mips64el-unknown-elf -march=mips64 -mabi=64 -msoft-float -mno-abicalls -fno-pic -G0 -ffreestanding -fno-builtin -fno-stack-protector -std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-vectorize -fno-slp-vectorize -Iinclude"
            n64_on="-target mips64el-unknown-elf -march=mips64 -mabi=64 -msoft-float -mno-abicalls -fno-pic -G0 -ffreestanding -fno-builtin -fno-stack-protector -std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fvectorize -fslp-vectorize -Iinclude"
            n64_as="-target mips64el-unknown-elf -march=mips64 -mabi=64 -msoft-float -mno-abicalls"
        else
            CC_N64=$GCC
            n64_off="-march=mips64 -mabi=64 -msoft-float -mno-abicalls -fno-pic -G0 -ffreestanding -fno-builtin -fno-stack-protector -std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-tree-vectorize -fno-tree-slp-vectorize -Iinclude"
            n64_on="-march=mips64 -mabi=64 -msoft-float -mno-abicalls -fno-pic -G0 -ffreestanding -fno-builtin -fno-stack-protector -std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -ftree-vectorize -ftree-slp-vectorize -Iinclude"
            n64_as="-march=mips64 -mabi=64 -msoft-float -mno-abicalls"
        fi
        echo "mips: N64 emulator is qemu-system-mips64el -M malta -cpu R4000"
        echo "mips: CP0 Count is the QEMU clock, not a 93.75 MHz VR4300"
        set -- $n64_as
        "$CC_N64" "$@" -c -o "$OBJ/malta-start.o" verify/suite/malta_start.s
        set -- $n64_off
        "$CC_N64" "$@" -S -o "$OBJ/n64-mem-off.s" src/common/scalar/mem.c
        if grep -E '^[[:space:]]*(lq|sq)[[:space:]]' "$OBJ/n64-mem-off.s"; then
            echo "mips: N64 scalar-off emitted LQ or SQ" >&2
            exit 1
        fi
        if ! grep -E '^[[:space:]]*(ld|sd)[[:space:]]' "$OBJ/n64-mem-off.s" >/dev/null; then
            echo "mips: N64 scalar-off did not emit ld/sd" >&2
            exit 1
        fi
        "$CC_N64" "$@" -c -o "$OBJ/n64-mem-off.o" src/common/scalar/mem.c
        "$CC_N64" "$@" -c -o "$OBJ/n64-string-off.o" src/common/scalar/string.c
        "$CC_N64" "$@" -DRT_MALTA -DRT_BINARY='"n64-scalar-off"' \
            -c -o "$OBJ/n64-bench-off.o" verify/suite/ps2_bench.c
        set -- $n64_on
        "$CC_N64" "$@" -DRT_VECTORIZE -c -o "$OBJ/n64-mem-on.o" src/common/scalar/mem.c
        "$CC_N64" "$@" -DRT_VECTORIZE -c -o "$OBJ/n64-string-on.o" src/common/scalar/string.c
        "$CC_N64" "$@" -DRT_VECTORIZE -DRT_MALTA -DRT_BINARY='"n64-scalar-on"' \
            -c -o "$OBJ/n64-bench-on.o" verify/suite/ps2_bench.c
        set -- $n64_off
        "$CC_N64" "$@" -DRT_MALTA -DRT_WITH_RCP -DRT_BINARY='"n64-rcp"' \
            -c -o "$OBJ/n64-bench-rcp.o" verify/suite/ps2_bench.c
        link_n64 "$OBJ/n64-scalar-off.elf" "$OBJ/malta-start.o" \
            "$OBJ/n64-bench-off.o" "$OBJ/n64-mem-off.o" "$OBJ/n64-string-off.o"
        link_n64 "$OBJ/n64-scalar-on.elf" "$OBJ/malta-start.o" \
            "$OBJ/n64-bench-on.o" "$OBJ/n64-mem-on.o" "$OBJ/n64-string-on.o"
        link_n64 "$OBJ/n64-rcp.elf" "$OBJ/malta-start.o" \
            "$OBJ/n64-bench-rcp.o" "$OBJ/n64-mem-off.o" "$OBJ/n64-string-off.o" \
            "$OBJ/rcp-mem-n64.o" "$OBJ/rcp-string-n64.o"
        run_malta n64-scalar-off "$OBJ/n64-scalar-off.elf"
        run_malta n64-scalar-on "$OBJ/n64-scalar-on.elf"
        run_malta n64-rcp "$OBJ/n64-rcp.elf"
        ran=1
    fi
fi

if [ "$ran" -ne 1 ]; then
    echo "mips: nothing ran. Need PCSX2 or qemu-system-mips64el." >&2
    exit 1
fi
