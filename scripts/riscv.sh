#!/bin/sh
# RVV32 contract under QEMU virt, no guest libc.
# riscv64 ASCII tables against Alpine 3.24.4 musl: C99 scalar, then RVV.
# Alpine has no riscv32 userland. Guest nanoseconds are the guest clock,
# not a silicon result.
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
        -cpu rv${xlen},v=true,vlen=128,elen=64 \
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
    if ! grep -q 'rvv ok' "$log"; then
        echo "rvv${xlen}: missing rvv ok" >&2
        return 1
    fi
    echo "rvv${xlen}: exit 0"
}

ALPINE="3.24.4"
MUSL="1.2.6-r3"
KPKG="6.18.63-r0"
BASE="https://dl-cdn.alpinelinux.org/alpine/v3.24"
cache="$(pwd)/verify/.cache"
sys="$cache/sysroot-riscv64"
obj="$cache/obj-riscv64"
root="$cache/root-riscv64"
kern="$cache/Image-${KPKG}-riscv64"
initrd="$cache/rt-initrd-rvv64.gz"

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

run_rv64_table() {
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
    if [ ! -f "$kern" ]; then
        kdir=$(mktemp -d "${TMPDIR:-/tmp}/rt-kern.XXXXXX")
        echo "riscv: unpack linux-lts"
        extract_apk "$cache/linux-lts-${KPKG}-riscv64.apk" "$kdir" boot/vmlinuz-lts
        gzip -dc "$kdir/vmlinuz-lts" > "$kern.partial"
        mv "$kern.partial" "$kern"
        rm -rf "$kdir"
    fi
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
    mkdir -p "$root/rt" "$obj"
    res=$("$CC" -print-resource-dir)
    cflags="-std=c99 -O2 -Wall -Wextra -Werror -Wno-unused-function \
-fno-strict-aliasing -fno-builtin -fno-stack-protector -fno-pie \
-nostdinc -isystem $res/include"
    scflags="$cflags -fno-vectorize -fno-slp-vectorize"
    echo "riscv: compile scalar riscv64 table"
    # /bin/sh splits these flag lists.
    # shellcheck disable=SC2086
    "$CC" -target riscv64-linux-musl -march=rv64gc -mabi=lp64d $scflags \
        -isystem "$sys/usr/include" -Iinclude -DRT_TABLE_SCALAR \
        -c -o "$obj/test_host_scalar.o" verify/suite/test_host.c
    "$CC" -target riscv64-linux-musl -march=rv64gc -mabi=lp64d $scflags \
        -isystem "$sys/usr/include" -Iinclude \
        -S -o "$obj/mem_scalar.s" src/common/scalar/mem.c
    "$CC" -target riscv64-linux-musl -march=rv64gc -mabi=lp64d $scflags \
        -isystem "$sys/usr/include" -Iinclude \
        -S -o "$obj/string_scalar.s" src/common/scalar/string.c
    if grep -E 'vset|vle[0-9]|vse[0-9]|vlux|vsox' \
        "$obj/mem_scalar.s" "$obj/string_scalar.s"; then
        echo "riscv: scalar objects contain vector opcodes" >&2
        exit 1
    fi
    "$CC" -target riscv64-linux-musl -march=rv64gc -mabi=lp64d \
        -c -o "$obj/mem_scalar.o" "$obj/mem_scalar.s"
    "$CC" -target riscv64-linux-musl -march=rv64gc -mabi=lp64d \
        -c -o "$obj/string_scalar.o" "$obj/string_scalar.s"
    "$LD" -m elf64lriscv \
        -dynamic-linker /lib/ld-musl-riscv64.so.1 \
        "$sys/usr/lib/crt1.o" \
        "$sys/usr/lib/crti.o" \
        "$obj/test_host_scalar.o" "$obj/mem_scalar.o" "$obj/string_scalar.o" \
        "$root/lib/ld-musl-riscv64.so.1" \
        "$sys/usr/lib/crtn.o" \
        -o "$obj/test_host_scalar"
    for sym in rt_memcpy_scalar rt_memmove_scalar rt_memset_scalar \
        rt_memcmp_scalar rt_strlen rt_strpad; do
        if ! strings "$obj/test_host_scalar" | grep -qx "$sym"; then
            echo "riscv: test_host_scalar is missing $sym" >&2
            exit 1
        fi
    done
    if strings "$obj/test_host_scalar" | grep -qx 'rt_memcpy_rvv'; then
        echo "riscv: scalar binary contains an RVV symbol" >&2
        exit 1
    fi
    echo "riscv: compile RVV64 table"
    # shellcheck disable=SC2086
    "$CC" -target riscv64-linux-musl -march=rv64gcv -mabi=lp64d $cflags \
        -isystem "$sys/usr/include" -Iinclude -DRT_TABLE_RVV \
        -c -o "$obj/test_host.o" verify/suite/test_host.c
    "$CC" -target riscv64-linux-musl -march=rv64gcv -mabi=lp64d \
        -c -o "$obj/mem.o" src/riscv64/rvv/mem.s
    "$CC" -target riscv64-linux-musl -march=rv64gcv -mabi=lp64d \
        -c -o "$obj/string.o" src/riscv64/rvv/string.s
    "$LD" -m elf64lriscv \
        -dynamic-linker /lib/ld-musl-riscv64.so.1 \
        "$sys/usr/lib/crt1.o" \
        "$sys/usr/lib/crti.o" \
        "$obj/test_host.o" "$obj/mem.o" "$obj/string.o" \
        "$root/lib/ld-musl-riscv64.so.1" \
        "$sys/usr/lib/crtn.o" \
        -o "$obj/test_host_rvv"
    for sym in rt_memcpy_rvv rt_memset_rvv rt_memcmp_rvv rt_strlen_rvv rt_strpad_rvv; do
        if ! strings "$obj/test_host_rvv" | grep -qx "$sym"; then
            echo "riscv: test_host_rvv is missing $sym" >&2
            exit 1
        fi
    done
    cp -f "$obj/test_host_scalar" "$root/rt/test_host_scalar"
    cp -f "$obj/test_host_rvv" "$root/rt/test_host_rvv"
    chmod 755 "$root/rt/test_host_scalar" "$root/rt/test_host_rvv"
    cat > "$root/init" <<'EOF'
#!/bin/sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export NO_COLOR=1
export TERM=dumb
mkdir -p /proc /sys
mount -t proc proc /proc
mount -t sysfs sysfs /sys
echo "======== scalar riscv64 Alpine musl ========"
/rt/test_host_scalar
echo "scalar64_exit:$?"
echo "======== RVV64 Alpine musl ========"
/rt/test_host_rvv
echo "rvv64_exit:$?"
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
    echo "riscv: pack riscv64 initrd"
    rm -f "$initrd.partial"
    (
        cd "$root"
        find . -print | cpio -o -H newc | gzip -9 > "$initrd.partial"
    )
    mv "$initrd.partial" "$initrd"
    echo "riscv: libc is Alpine ${ALPINE} musl ${MUSL}, riscv64"
    echo "riscv: scalar and RVV guest nanoseconds are the guest clock, not a silicon result"
    echo "riscv: strscpy, strscat, and strpad have no musl symbol"
    log="$cache/rvv64-table.log"
    fifo="$cache/rvv64-table.fifo"
    rm -f "$fifo" "$log"
    mkfifo "$fifo"
    tee "$log" < "$fifo" &
    tpid=$!
    qemu-system-riscv64 \
        -machine virt \
        -cpu rv64,v=true,vlen=128,elen=64 \
        -accel tcg -m 512 -smp 1 \
        -nic none \
        -kernel "$kern" \
        -initrd "$initrd" \
        -append "console=ttyS0 loglevel=3 quiet panic=1 rdinit=/init" \
        -nographic -no-reboot \
        >"$fifo" 2>&1 &
    qpid=$!
    (
        slept=0
        while [ "$slept" -lt 600 ]; do
            if ! kill -0 "$qpid" 2>/dev/null; then
                exit 0
            fi
            sleep 1
            slept=$((slept + 1))
        done
        echo "riscv: RVV64 table qemu exceeded 600s" >&2
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
    echo "riscv: riscv64 qemu process exit ${qec}"
    got=$(grep '^scalar64_exit:' "$log" | tail -n 1 | tr -d '\r' | sed 's/^scalar64_exit://') || true
    if [ "$got" != "0" ]; then
        echo "riscv: scalar64_exit:${got:-missing}" >&2
        exit 1
    fi
    got=$(grep '^rvv64_exit:' "$log" | tail -n 1 | tr -d '\r' | sed 's/^rvv64_exit://') || true
    if [ "$got" != "0" ]; then
        echo "riscv: rvv64_exit:${got:-missing}" >&2
        exit 1
    fi
    if ! grep -q '== backend: scalar ==' "$log"; then
        echo "riscv: missing backend table: scalar" >&2
        exit 1
    fi
    if ! grep -q '== backend: rvv ==' "$log"; then
        echo "riscv: missing backend table: rvv" >&2
        exit 1
    fi
    if ! grep -q '| memmove ' "$log"; then
        echo "riscv: scalar table is missing memmove" >&2
        exit 1
    fi
    n=$(grep -c '| strscpy          |      N/A |' "$log" || true)
    if [ "$n" -lt 2 ]; then
        echo "riscv: strscpy libc cell is not N/A in both tables" >&2
        exit 1
    fi
    echo "riscv: scalar and RVV64 tables ok"
}

echo "riscv: $CC"
compile_width 64 lp64
compile_width 32 ilp32
run_width 64
run_width 32
echo "riscv: RVV32 contract ok (Alpine publishes no riscv32 libc)"
run_rv64_table
echo "riscv: RVV32 contract, scalar riscv64 table, and RVV64 table ok"
