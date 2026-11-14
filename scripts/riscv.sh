#!/bin/sh
# RVV32 and RVV64 freestanding contracts, then two musl guests.
# rv32: Bootlin 2026.08 ilp32d. rv64: Alpine 3.24.4.
# Each guest runs scalar C99 with vectorizers off, scalar C99 with
# vectorizers on, and the RVV assembly. Guest nanoseconds are the
# guest clock, not a silicon result.
set -eu
cd "$(dirname "$0")/.."

mkdir -p build
LOG=build/riscv.log

cc_supports_riscv() {
    printf 'int probe;\n' > build/cc-probe.c
    if "$1" -target riscv64-unknown-elf -c -o build/cc-probe.o build/cc-probe.c >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

CC=""
if [ -n "${CC_RISCV:-}" ] && cc_supports_riscv "$CC_RISCV"; then
    CC=$CC_RISCV
elif command -v clang >/dev/null 2>&1 && cc_supports_riscv clang; then
    CC=clang
elif [ -x /opt/homebrew/opt/llvm/bin/clang ] && cc_supports_riscv /opt/homebrew/opt/llvm/bin/clang; then
    CC=/opt/homebrew/opt/llvm/bin/clang
fi
if [ -z "$CC" ]; then
    echo "riscv: need a clang that accepts -target riscv64-unknown-elf" >&2
    exit 1
fi

if command -v ld.lld >/dev/null 2>&1; then
    LD=ld.lld
elif [ -x /opt/homebrew/bin/ld.lld ]; then
    LD=/opt/homebrew/bin/ld.lld
else
    echo "riscv: ld.lld not found" >&2
    exit 1
fi

command -v qemu-system-riscv64 >/dev/null 2>&1 || {
    echo "riscv: qemu-system-riscv64 not found" >&2
    exit 1
}
command -v qemu-system-riscv32 >/dev/null 2>&1 || {
    echo "riscv: qemu-system-riscv32 not found" >&2
    exit 1
}

compile_width() {
    xlen=$1
    abi=$2
    elf=build/rvv${xlen}.elf
    march=rv${xlen}gcv
    target=riscv${xlen}-unknown-elf
    base="-target $target -march=$march -mabi=$abi"
    cflags="$base -mcmodel=medany -std=c99 -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector -fno-vectorize -fno-slp-vectorize -Iinclude"
    # POSIX sh splits these flag lists on purpose.
    set -- $base
    "$CC" "$@" -c -o build/rvv${xlen}-start.o verify/suite/rvv_start.s
    "$CC" "$@" -c -o build/rvv${xlen}-mem.o src/riscv${xlen}/rvv/mem.s
    "$CC" "$@" -c -o build/rvv${xlen}-string.o src/riscv${xlen}/rvv/string.s
    set -- $cflags
    "$CC" "$@" -c -o build/rvv${xlen}-test.o verify/suite/test_rvv.c
    "$LD" -m elf${xlen}lriscv -z max-page-size=4096 -T verify/suite/rvv.ld -o "$elf" \
        build/rvv${xlen}-start.o build/rvv${xlen}-mem.o \
        build/rvv${xlen}-string.o build/rvv${xlen}-test.o
}

run_width() {
    xlen=$1
    elf=build/rvv${xlen}.elf
    log=build/rvv${xlen}.log
    : > "$log"
    qemu-system-riscv${xlen} \
        -machine virt \
        -cpu rv${xlen},v=true,vext_spec=v1.0,vlen=128,elen=64 \
        -m 4M \
        -bios none \
        -display none \
        -monitor none \
        -serial stdio \
        -kernel "$elf" >"$log" 2>&1 &
    pid=$!
    n=0
    while kill -0 "$pid" 2>/dev/null; do
        n=$((n + 1))
        if [ "$n" -gt 90 ]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            echo "rvv${xlen}: timeout" >&2
            cat "$log" >&2
            return 1
        fi
        sleep 1
    done
    rc=0
    wait "$pid" || rc=$?
    cat "$log"
    if [ "$rc" -ne 0 ]; then
        echo "rvv${xlen}: exit $rc" >&2
        return 1
    fi
    if ! grep -a -q 'rvv ok' "$log"; then
        echo "rvv${xlen}: missing rvv ok" >&2
        return 1
    fi
    echo "rvv${xlen}: exit 0"
}

ALPINE="3.24.4"
MUSL="1.2.6-r3"
KPKG="6.18.63-r0"
BASE="https://dl-cdn.alpinelinux.org/alpine/v3.24"
BOOTLIN="https://toolchains.bootlin.com/downloads/releases/toolchains/riscv32-ilp32d/test-system"
cache="$(pwd)/verify/.cache"
sys="$cache/sysroot-riscv64"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "riscv: $1 not on PATH" >&2
        exit 1
    fi
}

fetch() {
    url=$1
    dest=$2
    if [ -f "$dest" ]; then
        return 0
    fi
    echo "riscv: fetch $url"
    curl -fL --retry 3 --retry-delay 2 --silent --show-error \
        -o "$dest.partial" "$url"
    mv "$dest.partial" "$dest"
}

# Ubuntu 24.04's QEMU package ships the rv64 OpenSBI blob only.
# rv32 must be named with -bios or the guest exits before /init.
resolve_bios() {
    xlen=$1
    name=opensbi-riscv${xlen}-generic-fw_dynamic.bin
    dest="$cache/$name"
    if [ -f "$dest" ]; then
        printf '%s\n' "$dest"
        return 0
    fi
    for p in \
        "/usr/share/qemu/$name" \
        "/usr/lib/riscv${xlen}-linux-gnu/opensbi/generic/fw_dynamic.bin" \
        "/opt/homebrew/share/qemu/$name" \
        "/usr/local/share/qemu/$name"
    do
        if [ -f "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    mkdir -p "$cache"
    echo "riscv: fetch OpenSBI rv${xlen} fw_dynamic" >&2
    curl -fL --retry 3 --retry-delay 2 --silent --show-error \
        -o "$dest.partial" \
        "https://raw.githubusercontent.com/qemu/qemu/v10.0.0/pc-bios/$name"
    mv "$dest.partial" "$dest"
    if [ ! -s "$dest" ]; then
        echo "riscv: OpenSBI rv${xlen} firmware is empty" >&2
        exit 1
    fi
    printf '%s\n' "$dest"
}

extract_apk() {
    src=$1
    dest=$2
    only=${3:-}
    rm -rf "$dest"
    mkdir -p "$dest"
    python3 - "$src" "$dest" "$only" <<'PY'
import gzip, io, sys, tarfile
src, dest, only = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(src, "rb").read()
pos = 0
while True:
    at = data.find(b"\x1f\x8b", pos)
    if at < 0:
        sys.stderr.write("riscv: %s has no tar member\n" % src)
        sys.exit(1)
    try:
        payload = gzip.GzipFile(fileobj=io.BytesIO(data[at:])).read()
        tf = tarfile.open(fileobj=io.BytesIO(payload))
    except Exception:
        pos = at + 2
        continue
    kwargs = {}
    if hasattr(tarfile, "data_filter"):
        kwargs["filter"] = "data"
    if only:
        member = tf.extractfile(only)
        if member is None:
            sys.stderr.write("riscv: %s missing %s\n" % (src, only))
            sys.exit(1)
        out = dest + "/" + only.split("/")[-1]
        with open(out, "wb") as fh:
            fh.write(member.read())
    else:
        tf.extractall(dest, **kwargs)
    sys.exit(0)
PY
}

need_sym() {
    bin=$1
    sym=$2
    if ! strings "$bin" | grep -qx "$sym"; then
        echo "riscv: $(basename "$bin") is missing $sym" >&2
        exit 1
    fi
}

reject_sym() {
    bin=$1
    sym=$2
    if strings "$bin" | grep -qx "$sym"; then
        echo "riscv: $(basename "$bin") contains $sym" >&2
        exit 1
    fi
}

need_exit() {
    key=$1
    log=$2
    got=$(grep -a "^${key}:" "$log" | tail -n 1 | tr -d '\r' | sed "s/^${key}://") || true
    if [ "$got" != "0" ]; then
        echo "riscv: ${key}:${got:-missing}" >&2
        exit 1
    fi
}

count_at_least() {
    pat=$1
    log=$2
    min=$3
    n=$(grep -a -F -c "$pat" "$log" || true)
    if [ "${n:-0}" -lt "$min" ]; then
        echo "riscv: expected >= $min of [$pat], saw ${n:-0}" >&2
        exit 1
    fi
}

link_one() {
    out=$1
    shift
    set -- "$LD" -m "$g_ld" -dynamic-linker "$g_dyn" \
        "$g_crt1" "$g_crti" "$@"
    if [ -n "$g_extra" ]; then
        set -- "$@" "$g_extra"
    fi
    if [ -n "$g_libdir" ]; then
        set -- "$@" -L "$g_libdir" -lc
    else
        set -- "$@" "$g_libcso"
    fi
    if [ -n "$g_rtlib" ] && [ -f "$g_rtlib" ]; then
        set -- "$@" "$g_rtlib"
    fi
    set -- "$@" "$g_crtn" -o "$out"
    "$@"
}

prepare_rv64() {
    need_tool curl
    need_tool python3
    need_tool tar
    need_tool gzip
    need_tool cpio
    need_tool strings
    mkdir -p "$cache"
    fetch "$BASE/releases/riscv64/alpine-minirootfs-${ALPINE}-riscv64.tar.gz" \
        "$cache/alpine-minirootfs-${ALPINE}-riscv64.tar.gz"
    fetch "$BASE/main/riscv64/musl-dev-${MUSL}.apk" \
        "$cache/musl-dev-${MUSL}-riscv64.apk"
    fetch "$BASE/main/riscv64/linux-lts-${KPKG}.apk" \
        "$cache/linux-lts-${KPKG}-riscv64.apk"
    if [ ! -f "$sys/usr/lib/crt1.o" ]; then
        echo "riscv: unpack riscv64 musl sysroot"
        extract_apk "$cache/musl-dev-${MUSL}-riscv64.apk" "$sys"
    fi
    kern="$cache/Image-${KPKG}-riscv64"
    if [ ! -f "$kern" ]; then
        kdir=$(mktemp -d "${TMPDIR:-/tmp}/rt-kern.XXXXXX")
        echo "riscv: unpack linux-lts"
        extract_apk "$cache/linux-lts-${KPKG}-riscv64.apk" "$kdir" boot/vmlinuz-lts
        gzip -dc "$kdir/vmlinuz-lts" > "$kern.partial"
        mv "$kern.partial" "$kern"
        rm -rf "$kdir"
    fi
    root="$cache/root-riscv64"
    if [ ! -f "$root/lib/ld-musl-riscv64.so.1" ]; then
        echo "riscv: unpack Alpine minirootfs"
        rm -rf "$root"
        mkdir -p "$root"
        tar -xzf "$cache/alpine-minirootfs-${ALPINE}-riscv64.tar.gz" -C "$root"
    fi
    if [ ! -x "$root/bin/busybox" ] || [ ! -f "$root/lib/ld-musl-riscv64.so.1" ]; then
        echo "riscv: minirootfs is missing busybox or musl" >&2
        exit 1
    fi
    g_xlen=64
    g_abi=lp64d
    g_ld=elf64lriscv
    g_dyn=/lib/ld-musl-riscv64.so.1
    g_sysinc=$sys/usr/include
    g_crt1=$sys/usr/lib/crt1.o
    g_crti=$sys/usr/lib/crti.o
    g_crtn=$sys/usr/lib/crtn.o
    g_libcso=$root/lib/ld-musl-riscv64.so.1
    g_libdir=""
    g_root=$root
    g_kern=$kern
    g_cpu="rv64,v=true,vext_spec=v1.0,vlen=128,elen=64"
    g_libc="Alpine musl"
    g_obj=$cache/obj-riscv64
    g_initrd=$cache/rt-initrd-rvv64.gz
    g_log=$cache/rvv64-table.log
}

ensure_rv32_musl() {
    inc="$cache/musl-rv32/include/string.h"
    crt1="$cache/musl-rv32/lib/crt1.o"
    crti="$cache/musl-rv32/lib/crti.o"
    crtn="$cache/musl-rv32/lib/crtn.o"
    if [ -f "$inc" ] && [ -f "$crt1" ] && [ -f "$crti" ] && [ -f "$crtn" ]; then
        return 0
    fi
    echo "riscv: build riscv32 musl headers and crt"
    fetch "https://musl.libc.org/releases/musl-1.2.6.tar.gz" \
        "$cache/musl-1.2.6.tar.gz"
    rm -rf "$cache/musl-src"
    mkdir -p "$cache/musl-src"
    tar -xzf "$cache/musl-1.2.6.tar.gz" -C "$cache/musl-src" --strip-components 1
    jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
    (
        cd "$cache/musl-src"
        CC="$CC -target riscv32-linux-musl -march=rv32gc -mabi=ilp32d" \
            AR=ar RANLIB=ranlib \
            ./configure --prefix="$cache/musl-rv32" \
            --target=riscv32-linux-musl --disable-shared
        make -j"$jobs" AR=ar RANLIB=ranlib
        make install AR=ar RANLIB=ranlib
    )
    if [ ! -f "$inc" ] || [ ! -f "$crt1" ] || [ ! -f "$crti" ] || [ ! -f "$crtn" ]; then
        echo "riscv: riscv32 musl headers or crt missing after install" >&2
        exit 1
    fi
}

prepare_rv32() {
    need_tool curl
    need_tool python3
    need_tool tar
    need_tool gzip
    need_tool cpio
    need_tool strings
    mkdir -p "$cache"
    fetch "$BOOTLIN/riscv32-ilp32d--musl--stable-2026.08-1-Image" \
        "$cache/Image-bootlin-rv32-musl"
    fetch "$BOOTLIN/riscv32-ilp32d--musl--stable-2026.08-1-rootfs.tar" \
        "$cache/rootfs-bootlin-rv32-musl.tar"
    ensure_rv32_musl
    root="$cache/root-riscv32"
    if [ ! -x "$root/bin/busybox" ] || [ ! -f "$root/lib/libc.so" ]; then
        echo "riscv: unpack Bootlin riscv32 rootfs"
        rm -rf "$root"
        mkdir -p "$root"
        tar -xf "$cache/rootfs-bootlin-rv32-musl.tar" -C "$root"
    fi
    if [ ! -x "$root/bin/busybox" ] || [ ! -f "$root/lib/libc.so" ]; then
        echo "riscv: Bootlin rootfs is missing busybox or musl" >&2
        exit 1
    fi
    g_xlen=32
    g_abi=ilp32d
    g_ld=elf32lriscv
    g_dyn=/lib/ld-musl-riscv32.so.1
    g_sysinc=$cache/musl-rv32/include
    g_crt1=$cache/musl-rv32/lib/crt1.o
    g_crti=$cache/musl-rv32/lib/crti.o
    g_crtn=$cache/musl-rv32/lib/crtn.o
    g_libcso=$root/lib/libc.so
    g_libdir=$root/lib
    g_root=$root
    g_kern=$cache/Image-bootlin-rv32-musl
    g_cpu="rv32,v=true,vext_spec=v1.0,vlen=128,elen=64,f=true,d=true"
    g_libc="Bootlin musl"
    g_obj=$cache/obj-riscv32
    g_initrd=$cache/rt-initrd-rvv32.gz
    g_log=$cache/rvv32-table.log
}

build_and_boot() {
    res=$("$CC" -print-resource-dir)
    target=riscv${g_xlen}-linux-musl
    g_rtlib=$("$CC" -target "$target" -mabi="$g_abi" --rtlib=compiler-rt -print-libgcc-file-name)
    case "$g_rtlib" in
        /*) ;;
        *) g_rtlib="" ;;
    esac
    common="-std=c99 -O2 -Wall -Wextra -Werror -Wno-unused-function \
-fno-strict-aliasing -fno-builtin -fno-stack-protector -fno-pie \
-nostdinc -isystem $res/include -isystem $g_sysinc -Iinclude"
    off="$common -fno-vectorize -fno-slp-vectorize"
    g_extra=""
    mkdir -p "$g_obj" "$g_root/rt"
    if [ "$g_xlen" = 32 ]; then
        # ilp32d has no compiler-rt in this clang. Unsigned long long
        # to double is the one helper test_host.c emits.
        cat > "$g_obj/floatundidf.c" <<'EOF'
double __floatundidf(unsigned long long a)
{
    double hi = (double)(unsigned)(a >> 32);
    double lo = (double)(unsigned)a;
    return hi * 4294967296.0 + lo;
}
EOF
        "$CC" -target riscv32-linux-musl -march=rv32gc -mabi=ilp32d -O2 \
            -c -o "$g_obj/floatundidf.o" "$g_obj/floatundidf.c"
        g_extra=$g_obj/floatundidf.o
    fi

    echo "riscv: compile scalar riscv${g_xlen} (vectorize off)"
    # /bin/sh splits these flag lists.
    # shellcheck disable=SC2086
    "$CC" -target "$target" -march=rv${g_xlen}gc -mabi="$g_abi" $off \
        -DRT_TABLE_SCALAR \
        -c -o "$g_obj/test_off.o" verify/suite/test_host.c
    "$CC" -target "$target" -march=rv${g_xlen}gc -mabi="$g_abi" $off \
        -S -o "$g_obj/mem_off.s" src/common/scalar/mem.c
    "$CC" -target "$target" -march=rv${g_xlen}gc -mabi="$g_abi" $off \
        -S -o "$g_obj/string_off.s" src/common/scalar/string.c
    if grep -E 'vset|vle[0-9]|vse[0-9]|vlux|vsox' \
        "$g_obj/mem_off.s" "$g_obj/string_off.s"; then
        echo "riscv: scalar-off objects contain vector opcodes" >&2
        exit 1
    fi
    "$CC" -target "$target" -march=rv${g_xlen}gc -mabi="$g_abi" \
        -c -o "$g_obj/mem_off.o" "$g_obj/mem_off.s"
    "$CC" -target "$target" -march=rv${g_xlen}gc -mabi="$g_abi" \
        -c -o "$g_obj/string_off.o" "$g_obj/string_off.s"
    link_one "$g_obj/test_host_scalar" \
        "$g_obj/test_off.o" "$g_obj/mem_off.o" "$g_obj/string_off.o"

    echo "riscv: compile scalar riscv${g_xlen} (vectorize on)"
    # shellcheck disable=SC2086
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" $common \
        -DRT_TABLE_SCALAR -DRT_VECTORIZE \
        -c -o "$g_obj/test_on.o" verify/suite/test_host.c
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" $common \
        -DRT_VECTORIZE \
        -S -o "$g_obj/mem_on.s" src/common/scalar/mem.c
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" $common \
        -DRT_VECTORIZE \
        -S -o "$g_obj/string_on.s" src/common/scalar/string.c
    if ! grep -E 'vset|vle[0-9]|vse[0-9]' "$g_obj/mem_on.s" >/dev/null; then
        echo "riscv: scalar-on memory was not vectorized" >&2
        exit 1
    fi
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" \
        -c -o "$g_obj/mem_on.o" "$g_obj/mem_on.s"
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" \
        -c -o "$g_obj/string_on.o" "$g_obj/string_on.s"
    link_one "$g_obj/test_host_scalar_on" \
        "$g_obj/test_on.o" "$g_obj/mem_on.o" "$g_obj/string_on.o"

    echo "riscv: compile RVV${g_xlen}"
    # shellcheck disable=SC2086
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" $common \
        -DRT_TABLE_RVV \
        -c -o "$g_obj/test_rvv.o" verify/suite/test_host.c
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" \
        -c -o "$g_obj/mem_rvv.o" src/riscv${g_xlen}/rvv/mem.s
    "$CC" -target "$target" -march=rv${g_xlen}gcv -mabi="$g_abi" \
        -c -o "$g_obj/string_rvv.o" src/riscv${g_xlen}/rvv/string.s
    link_one "$g_obj/test_host_rvv" \
        "$g_obj/test_rvv.o" "$g_obj/mem_rvv.o" "$g_obj/string_rvv.o"

    for sym in rt_memcpy_scalar rt_memmove_scalar rt_memset_scalar \
        rt_memcmp_scalar rt_strlen rt_strpad; do
        need_sym "$g_obj/test_host_scalar" "$sym"
        need_sym "$g_obj/test_host_scalar_on" "$sym"
    done
    reject_sym "$g_obj/test_host_scalar" rt_memcpy_rvv
    reject_sym "$g_obj/test_host_scalar_on" rt_memcpy_rvv
    for sym in rt_memcpy_rvv rt_memset_rvv rt_memcmp_rvv \
        rt_strlen_rvv rt_strpad_rvv; do
        need_sym "$g_obj/test_host_rvv" "$sym"
    done

    cp -f "$g_obj/test_host_scalar" "$g_root/rt/test_host_scalar"
    cp -f "$g_obj/test_host_scalar_on" "$g_root/rt/test_host_scalar_on"
    cp -f "$g_obj/test_host_rvv" "$g_root/rt/test_host_rvv"
    chmod 755 "$g_root/rt/test_host_scalar" \
        "$g_root/rt/test_host_scalar_on" "$g_root/rt/test_host_rvv"
    cat > "$g_root/init" <<EOF
#!/bin/sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export NO_COLOR=1
export TERM=dumb
mkdir -p /proc /sys
mount -t proc proc /proc
mount -t sysfs sysfs /sys
echo "======== scalar riscv${g_xlen} ${g_libc} (vectorize off) ========"
/rt/test_host_scalar
echo "scalar${g_xlen}_off_exit:\$?"
echo "======== scalar riscv${g_xlen} ${g_libc} (vectorize on) ========"
/rt/test_host_scalar_on
echo "scalar${g_xlen}_on_exit:\$?"
echo "======== RVV${g_xlen} ${g_libc} ========"
/rt/test_host_rvv
echo "rvv${g_xlen}_exit:\$?"
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
    chmod 755 "$g_root/init"
    echo "riscv: pack riscv${g_xlen} initrd"
    rm -f "$g_initrd.partial"
    (
        cd "$g_root"
        find . -print | cpio -o -H newc | gzip -9 > "$g_initrd.partial"
    )
    mv "$g_initrd.partial" "$g_initrd"
    echo "riscv: libc is ${g_libc}, riscv${g_xlen}"
    echo "riscv: guest nanoseconds are the guest clock, not a silicon result"
    echo "riscv: strscpy, strscat, and strpad have no musl symbol"
    fifo="$g_log.fifo"
    rm -f "$fifo" "$g_log"
    mkfifo "$fifo"
    tee "$g_log" < "$fifo" &
    tpid=$!
    bios=$(resolve_bios "$g_xlen")
    echo "riscv: bios $bios"
    qemu-system-riscv${g_xlen} \
        -machine virt \
        -cpu "$g_cpu" \
        -bios "$bios" \
        -accel tcg -m 512 -smp 1 \
        -nic none \
        -kernel "$g_kern" \
        -initrd "$g_initrd" \
        -append "console=ttyS0 loglevel=3 quiet panic=1 rdinit=/init" \
        -nographic -no-reboot \
        >"$fifo" 2>&1 &
    qpid=$!
    (
        slept=0
        while [ "$slept" -lt 1500 ]; do
            if ! kill -0 "$qpid" 2>/dev/null; then
                exit 0
            fi
            sleep 1
            slept=$((slept + 1))
        done
        echo "riscv: riscv${g_xlen} table qemu exceeded 1500s" >&2
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
    rm -f "$fifo"
    echo "riscv: riscv${g_xlen} qemu process exit ${qec}"
    need_exit "scalar${g_xlen}_off_exit" "$g_log"
    need_exit "scalar${g_xlen}_on_exit" "$g_log"
    need_exit "rvv${g_xlen}_exit" "$g_log"
    count_at_least "vectorize: off" "$g_log" 1
    count_at_least "vectorize: on" "$g_log" 1
    count_at_least "== backend: scalar ==" "$g_log" 2
    count_at_least "== backend: rvv ==" "$g_log" 1
    count_at_least "| memmove " "$g_log" 2
    count_at_least "| strscpy          |      N/A |" "$g_log" 3
    count_at_least "scalar riscv${g_xlen} ${g_libc} (vectorize off)" "$g_log" 1
    count_at_least "scalar riscv${g_xlen} ${g_libc} (vectorize on)" "$g_log" 1
    count_at_least "RVV${g_xlen} ${g_libc}" "$g_log" 1
    echo "riscv: riscv${g_xlen} scalar off, scalar on, and RVV ok"
}

echo "riscv: $CC"
compile_width 64 lp64
compile_width 32 ilp32
run_width 64
run_width 32
echo "riscv: RVV32 and RVV64 contracts ok"
prepare_rv64
build_and_boot
prepare_rv32
build_and_boot
echo "riscv: rv32 Bootlin musl and rv64 Alpine musl: scalar off, scalar on, and RVV ok"
