#!/bin/sh
# Two Intel guests. Each image is Alpine, musl, and busybox. No installer,
# no disk, no apk. Each kernel plus its initrd stays at or under 50MB.
# Downloads live in verify/.cache and are not part of the tree.
#
# IA-32   qemu-system-i386
#   Alpine x86 minirootfs + vmlinuz-lts (CONFIG_X86_32)
#   oracle: i386 REP, MMX, SSE
# EM64T   qemu-system-x86_64
#   Alpine x86_64 minirootfs + vmlinuz-virt
#   oracle: SSE2, AVX, AVX2, AVX-512 (the AVX-512 row follows CPUID and XCR0)
#
# SSE2 here is the x86-64 kernel, so it runs on the EM64T machine.
# The IA-32 SSE kernel is Pentium III and does not use SSE2 integer ops.
# AVX is the Sandy Bridge kernel (ymm moves, no AVX2 integer ops).
#
# QEMU TCG executes i386, MMX, SSE, SSE2, and AVX2. AVX-512 is absent
# from TCG, so that table stays off. The avx512 object is still linked.
# On a machine with AVX512F and AVX512BW:
#   sh scripts/avx512.sh em64t kvm
# Guest nanoseconds are the guest clock. They are not a silicon result.
#
#   sh scripts/avx512.sh                 # both machines
#   sh scripts/avx512.sh ia32            # IA-32 only
#   sh scripts/avx512.sh em64t           # EM64T only
#   sh scripts/avx512.sh tcg             # both under TCG
#   sh scripts/avx512.sh ia32 kvm
#
# Anchored at the repo root. /bin/sh splits $cflags. Do not source this from zsh.
set -eu
cd "$(dirname "$0")/.."
export COPYFILE_DISABLE=1

ALPINE="3.24.4"
MUSL="1.2.6-r3"
BASE="https://dl-cdn.alpinelinux.org/alpine/v3.24"
CAP=52428800

cache="$(pwd)/verify/.cache"
obj="$cache/obj"
sys64="$cache/sysroot-x86_64"
sys32="$cache/sysroot-i386"
kernel64="$cache/vmlinuz-virt-${ALPINE}"
kernel32="$cache/vmlinuz-lts-x86-${ALPINE}"
initrd64="$cache/rt-initrd-em64t.gz"
initrd32="$cache/rt-initrd-ia32.gz"

which_m=both
accel_mode=auto
for arg in "$@"; do
    case "$arg" in
    both|ia32|em64t) which_m=$arg ;;
    auto|tcg|kvm) accel_mode=$arg ;;
    *)
        echo "usage: sh scripts/avx512.sh [both|ia32|em64t] [auto|tcg|kvm]" >&2
        exit 1
        ;;
    esac
done

need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "avx512: $1 not on PATH. $2" >&2
        exit 1
    fi
}

need clang "Install the Xcode command line tools."
need ld.lld "brew install llvm"
need curl "curl is required to fetch the Alpine image."
need perl "perl is required to unpack Alpine apk archives."
need tar "tar is required to unpack the minirootfs."
need gzip "gzip is required to pack the initrd."
need cpio "cpio is required to pack the initrd."
need strings "strings is required to check the guest binaries."
if [ "$which_m" = both ] || [ "$which_m" = ia32 ]; then
    need qemu-system-i386 "brew install qemu"
fi
if [ "$which_m" = both ] || [ "$which_m" = em64t ]; then
    need qemu-system-x86_64 "brew install qemu"
fi

use_kvm=0
if [ "$accel_mode" = kvm ]; then
    use_kvm=1
elif [ "$accel_mode" = auto ] && [ "$(uname -s)" = Linux ] &&
    [ "$(uname -m)" = x86_64 ] && [ -e /dev/kvm ]; then
    use_kvm=1
fi

if [ "$use_kvm" -eq 1 ]; then
    if [ ! -e /dev/kvm ]; then
        echo "avx512: kvm needs /dev/kvm." >&2
        echo "avx512: macOS HVF does not run an x86 guest. Use tcg." >&2
        exit 1
    fi
    accel=kvm
    cpu_args="-enable-kvm -cpu host"
else
    accel=tcg
    cpu_args="-accel tcg -cpu max"
fi

mkdir -p "$cache"

fetch() {
    url=$1
    dest=$2
    if [ -f "$dest" ]; then
        return 0
    fi
    echo "avx512: fetch $url"
    curl -fL --retry 3 --retry-delay 2 --silent --show-error \
        -o "$dest.partial" "$url"
    mv "$dest.partial" "$dest"
}

# Alpine apk is a signature plus one or more concatenated gzip tar members.
# macOS tar reads the first gzip member and leaves the rest.
extract_apk() {
    src=$1
    dest=$2
    members=$(mktemp -d "${TMPDIR:-/tmp}/rt-apk.XXXXXX")
    perl - "$src" "$members" <<'END'
use strict;
use warnings;
my ($src, $members) = @ARGV;
open my $in, "<:raw", $src or die "open $src: $!\n";
local $/;
my $data = <$in>;
close $in;
my $pos = 0;
my $n = 0;
while (1) {
    my $at = index($data, "\x1f\x8b", $pos);
    last if $at < 0;
    $n++;
    open my $out, ">:raw", "$members/m$n.gz" or die "open member: $!\n";
    print $out substr($data, $at);
    close $out;
    $pos = $at + 2;
}
die "no gzip payload in $src\n" if $n == 0;
END
    rm -rf "$dest"
    mkdir -p "$dest"
    got=0
    for member in "$members"/m*.gz; do
        if tar -tzf "$member" >/dev/null 2>&1; then
            tar -xzf "$member" -C "$dest"
            got=1
        fi
    done
    rm -rf "$members"
    if [ "$got" -ne 1 ]; then
        echo "avx512: $src has no tar member" >&2
        exit 1
    fi
}

bytes() {
    wc -c < "$1" | tr -d ' '
}

prepare_root() {
    archive=$1
    loader=$2
    soname=$3
    echo "avx512: unpack $(basename "$archive")"
    rm -rf "$root"
    mkdir -p "$root"
    tar -xzf "$archive" -C "$root"
    if [ ! -x "$root/bin/busybox" ] || [ ! -f "$root/lib/$loader" ]; then
        echo "avx512: minirootfs is missing busybox or $loader" >&2
        exit 1
    fi
    if [ ! -e "$root/lib/$soname" ]; then
        ln -s "$loader" "$root/lib/$soname"
    fi
    mkdir -p "$root/rt"
}

write_init() {
    title=$1
    bin=$2
    tag=$3
    cat > "$root/init" <<EOF
#!/bin/sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export NO_COLOR=1
export TERM=dumb
mkdir -p /proc /sys
mount -t proc proc /proc
mount -t sysfs sysfs /sys
echo "---- guest cpu ----"
grep -m1 'model name' /proc/cpuinfo || true
grep -m1 '^flags' /proc/cpuinfo || true
echo "======== ${title} ========"
/rt/${bin}
s=\$?
echo "${tag}_exit:\$s"
sleep 1
if [ -x /sbin/poweroff ]; then
    /sbin/poweroff -f
fi
if [ -x /bin/busybox ]; then
    /bin/busybox poweroff -f
fi
echo o > /proc/sysrq-trigger
echo "init: poweroff returned"
sleep 2
exit 1
EOF
    chmod 755 "$root/init"
}

pack_image() {
    label=$1
    kern=$2
    ird=$3
    echo "avx512: pack ${label} initrd"
    rm -f "$ird.partial"
    (
        cd "$root"
        find . -print | cpio -o -H newc | gzip -9 > "$ird.partial"
    )
    mv "$ird.partial" "$ird"
    kbytes=$(bytes "$kern")
    ibytes=$(bytes "$ird")
    total=$((kbytes + ibytes))
    echo "avx512: ${label} image ${total} bytes (kernel ${kbytes} + initrd ${ibytes}), cap ${CAP}"
    if [ "$total" -gt "$CAP" ]; then
        echo "avx512: ${label} image exceeds 50MB" >&2
        exit 1
    fi
}

qpid=
tpid=
wpid=
fifo=
log=
stop_qemu() {
    if [ -n "$wpid" ]; then
        kill "$wpid" 2>/dev/null || true
        wpid=
    fi
    if [ -n "$qpid" ]; then
        kill "$qpid" 2>/dev/null || true
        qpid=
    fi
    if [ -n "$tpid" ]; then
        kill "$tpid" 2>/dev/null || true
        tpid=
    fi
    if [ -n "$fifo" ]; then
        rm -f "$fifo"
    fi
}
trap stop_qemu EXIT INT TERM

boot_guest() {
    label=$1
    qbin=$2
    kern=$3
    ird=$4
    backends=$5
    log="$cache/${label}.log"
    fifo="$cache/${label}.fifo"
    rm -f "$fifo" "$log"
    mkfifo "$fifo"
    tee "$log" < "$fifo" &
    tpid=$!
    # shellcheck disable=SC2086
    "$qbin" \
        -m 512 -smp 1 \
        $cpu_args \
        -nic none \
        -kernel "$kern" \
        -initrd "$ird" \
        -append "console=ttyS0 loglevel=3 quiet panic=1 rdinit=/init" \
        -nographic -no-reboot \
        >"$fifo" 2>&1 &
    qpid=$!
    (
        slept=0
        while [ "$slept" -lt 300 ]; do
            if ! kill -0 "$qpid" 2>/dev/null; then
                exit 0
            fi
            sleep 1
            slept=$((slept + 1))
        done
        echo "avx512: ${label} qemu exceeded 300s" >&2
        kill "$qpid" 2>/dev/null || true
    ) &
    wpid=$!
    set +e
    wait "$qpid"
    qec=$?
    set -e
    kill "$wpid" 2>/dev/null || true
    wait "$wpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    qpid=
    tpid=
    wpid=
    rm -f "$fifo"
    fifo=

    echo "avx512: ${label} qemu process exit ${qec}"
    got=$(grep "^${label}_exit:" "$log" | tail -n 1 | tr -d '\r' | sed "s/^${label}_exit://") || true
    miss=0
    if [ "$got" != "0" ]; then
        echo "avx512: ${label}_exit:${got:-missing}" >&2
        miss=1
    fi
    if grep -E 'Kernel panic|invalid opcode|Attempted to kill init|init: poweroff returned' "$log" >/dev/null 2>&1; then
        echo "avx512: ${label} guest shutdown failed" >&2
        miss=1
    fi
    for backend in $backends; do
        if ! grep -q "== backend: ${backend} ==" "$log"; then
            echo "avx512: ${label} missing backend table: ${backend}" >&2
            miss=1
        fi
    done
    if [ "$label" = em64t ]; then
        if [ "$accel" = kvm ]; then
            if ! grep -q "== backend: avx512 ==" "$log"; then
                echo "avx512: em64t missing backend table: avx512" >&2
                miss=1
            fi
        elif grep -q "== backend: avx512 ==" "$log"; then
            echo "avx512: em64t printed the avx512 table"
        else
            echo "avx512: em64t avx512 table stayed off under TCG"
        fi
    fi
    if [ "$miss" -ne 0 ]; then
        exit 1
    fi
    echo "avx512: ${label}_exit:0"
}

res=$(clang -print-resource-dir)
# /bin/sh splits $cflags. Do not source this from zsh.
cflags="-std=c99 -O2 -Wall -Wextra -Werror -Wno-unused-function \
-fno-strict-aliasing -fno-builtin -fno-stack-protector -fno-pie \
-nostdinc -isystem $res/include"
rm -rf "$obj"
mkdir -p "$obj"

run_ia32() {
    fetch "$BASE/releases/x86/alpine-minirootfs-${ALPINE}-x86.tar.gz" \
        "$cache/alpine-minirootfs-${ALPINE}-x86.tar.gz"
    fetch "$BASE/releases/x86/netboot-${ALPINE}/vmlinuz-lts" "$kernel32"
    fetch "$BASE/main/x86/musl-${MUSL}.apk" \
        "$cache/musl-${MUSL}-i386.apk"
    fetch "$BASE/main/x86/musl-dev-${MUSL}.apk" \
        "$cache/musl-dev-${MUSL}-i386.apk"
    if [ ! -f "$sys32/usr/lib/crt1.o" ] || [ ! -f "$sys32/lib/ld-musl-i386.so.1" ]; then
        echo "avx512: unpack i386 musl sysroot"
        extract_apk "$cache/musl-dev-${MUSL}-i386.apk" "$sys32"
        musl_stage=$(mktemp -d "${TMPDIR:-/tmp}/rt-apk.XXXXXX")
        extract_apk "$cache/musl-${MUSL}-i386.apk" "$musl_stage"
        mkdir -p "$sys32/lib"
        cp -p "$musl_stage/lib/ld-musl-i386.so.1" "$sys32/lib/"
        ln -sfn ld-musl-i386.so.1 "$sys32/lib/libc.musl-x86.so.1"
        rm -rf "$musl_stage"
    fi
    root="$cache/root-ia32"
    prepare_root "$cache/alpine-minirootfs-${ALPINE}-x86.tar.gz" \
        ld-musl-i386.so.1 libc.musl-x86.so.1
    echo "avx512: compile i386 mmx sse"
    # shellcheck disable=SC2086
    clang -target i386-linux-musl $cflags \
        -isystem "$sys32/usr/include" -Iinclude -DRT_TABLE_SIMD \
        -c -o "$obj/test_host_i386.o" verify/suite/test_host.c
    clang -target i386-linux-musl -c -o "$obj/rep.o" src/i386/rep/mem.s
    clang -target i386-linux-musl -c -o "$obj/mmx.o" src/i386/mmx/mem.s
    clang -target i386-linux-musl -c -o "$obj/sse.o" src/i386/sse/mem.s
    ld.lld -m elf_i386 \
        -dynamic-linker /lib/ld-musl-i386.so.1 \
        "$sys32/usr/lib/crt1.o" \
        "$sys32/usr/lib/crti.o" \
        "$obj/test_host_i386.o" \
        "$obj/rep.o" "$obj/mmx.o" "$obj/sse.o" \
        "$sys32/lib/ld-musl-i386.so.1" \
        "$sys32/usr/lib/crtn.o" \
        -o "$obj/test_host_i386"
    for sym in rt_memcpy_i386 rt_memcpy_mmx rt_memcpy_sse; do
        if ! strings "$obj/test_host_i386" | grep -qx "$sym"; then
            echo "avx512: test_host_i386 is missing $sym" >&2
            exit 1
        fi
    done
    cp -f "$obj/test_host_i386" "$root/rt/"
    chmod 755 "$root/rt/test_host_i386"
    write_init "IA-32 i386 / mmx / sse" test_host_i386 ia32
    pack_image ia32 "$kernel32" "$initrd32"
    echo "avx512: IA-32 accel=${accel} ${cpu_args}"
    echo "avx512: IA-32 runs the 386 REP kernel, MMX, and SSE."
    echo "avx512: guest nanoseconds are emulation."
    boot_guest ia32 qemu-system-i386 "$kernel32" "$initrd32" "i386 mmx sse"
}

run_em64t() {
    fetch "$BASE/releases/x86_64/alpine-minirootfs-${ALPINE}-x86_64.tar.gz" \
        "$cache/alpine-minirootfs-${ALPINE}-x86_64.tar.gz"
    fetch "$BASE/releases/x86_64/netboot-${ALPINE}/vmlinuz-virt" "$kernel64"
    fetch "$BASE/main/x86_64/musl-dev-${MUSL}.apk" \
        "$cache/musl-dev-${MUSL}-x86_64.apk"
    if [ ! -f "$sys64/usr/lib/crt1.o" ]; then
        echo "avx512: unpack x86_64 musl sysroot"
        extract_apk "$cache/musl-dev-${MUSL}-x86_64.apk" "$sys64"
    fi
    root="$cache/root-em64t"
    prepare_root "$cache/alpine-minirootfs-${ALPINE}-x86_64.tar.gz" \
        ld-musl-x86_64.so.1 libc.musl-x86_64.so.1
    echo "avx512: compile sse2 avx avx2 avx512"
    # shellcheck disable=SC2086
    clang -target x86_64-linux-musl $cflags \
        -isystem "$sys64/usr/include" -Iinclude -DRT_TABLE_SIMD \
        -c -o "$obj/test_host_simd.o" verify/suite/test_host.c
    clang -target x86_64-linux-musl -c -o "$obj/sse2.o" src/x86_64/sse2/mem.s
    clang -target x86_64-linux-musl -c -o "$obj/avx.o" src/x86_64/avx/mem.s
    clang -target x86_64-linux-musl -c -o "$obj/avx2.o" src/x86_64/avx2/mem.s
    clang -target x86_64-linux-musl -c -o "$obj/avx512.o" src/x86_64/avx512/mem.s
    ld.lld -m elf_x86_64 \
        -dynamic-linker /lib/ld-musl-x86_64.so.1 \
        "$sys64/usr/lib/crt1.o" \
        "$sys64/usr/lib/crti.o" \
        "$obj/test_host_simd.o" \
        "$obj/sse2.o" "$obj/avx.o" "$obj/avx2.o" "$obj/avx512.o" \
        "$root/lib/ld-musl-x86_64.so.1" \
        "$sys64/usr/lib/crtn.o" \
        -o "$obj/test_host_simd"
    for sym in rt_memcpy_sse2 rt_memcpy_avx rt_memcpy_avx2 rt_memcpy_avx512; do
        if ! strings "$obj/test_host_simd" | grep -qx "$sym"; then
            echo "avx512: test_host_simd is missing $sym" >&2
            exit 1
        fi
    done
    cp -f "$obj/test_host_simd" "$root/rt/"
    chmod 755 "$root/rt/test_host_simd"
    write_init "EM64T sse2 / avx / avx2 / avx512" test_host_simd em64t
    pack_image em64t "$kernel64" "$initrd64"
    if [ "$accel" = tcg ]; then
        echo "avx512: EM64T accel=tcg cpu=max"
        echo "avx512: EM64T runs SSE2, AVX, and AVX2."
        echo "avx512: AVX-512 is absent from TCG. The avx512 object stays linked."
        echo "avx512: the avx512 table is printed when CPUID has AVX512F+BW and XCR0 has the ZMM state."
        echo "avx512: guest nanoseconds are emulation."
        echo "avx512: on an AVX-512 host, sh scripts/avx512.sh em64t kvm"
        echo "avx512:   qemu-system-x86_64 -cpu host -enable-kvm -m 512 -smp 1 -nic none \\"
        echo "avx512:     -kernel verify/.cache/vmlinuz-virt-${ALPINE} -initrd verify/.cache/rt-initrd-em64t.gz \\"
        echo "avx512:     -append 'console=ttyS0 loglevel=3 quiet panic=1 rdinit=/init' \\"
        echo "avx512:     -nographic -no-reboot"
    else
        echo "avx512: EM64T accel=kvm cpu=host"
        echo "avx512: the guest CPUID selects sse2, avx, avx2, and avx512."
        echo "avx512: guest nanoseconds are the guest clock."
    fi
    boot_guest em64t qemu-system-x86_64 "$kernel64" "$initrd64" "sse2 avx avx2"
}

if [ "$which_m" = both ] || [ "$which_m" = ia32 ]; then
    run_ia32
fi
if [ "$which_m" = both ] || [ "$which_m" = em64t ]; then
    run_em64t
fi
