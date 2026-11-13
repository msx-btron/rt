#!/bin/sh
# i386 backend tables under QEMU.
# Linux x86_64: qemu-i386 user-mode + gcc -m32 (fast path).
# macOS ARM:   qemu-system-x86_64 + Alpine Linux VM (no Docker).
# Anchored at the repo root. The Alpine ISO stays in verify/.cache.
set -eu
cd "$(dirname "$0")/.."

host_arch=$(uname -m 2>/dev/null || echo unknown)
host_os=$(uname -s 2>/dev/null || echo unknown)
target=${1:-pentium3}

# ---------- Linux native user-mode path ----------
linux_usermode() {
    if ! command -v qemu-i386 >/dev/null 2>&1; then
        echo "qemu-i386 not found. On Debian/Ubuntu: apt install qemu-user gcc-multilib" >&2
        exit 1
    fi
    cc=${CC:-cc}
    if ! echo 'int main(void){return 0;}' | $cc -m32 -x c - -o /tmp/rt_m32_probe 2>/dev/null; then
        echo "cc -m32 failed. Install gcc-multilib / libc6-dev-i386." >&2
        exit 1
    fi
    cflags="-std=c99 -O2 -Wall -Wextra -Werror -fno-strict-aliasing -fno-builtin -Iinclude"
    scalar="src/common/scalar/mem.c src/common/scalar/string.c \
src/common/scalar/stdlib.c src/common/scalar/stdio.c"
    mkdir -p build
    $cc $cflags -m32 -static -o build/test_host32s verify/suite/test_host.c $scalar \
        src/i386/rep/mem.s src/i386/mmx/mem.s src/i386/sse/mem.s
    cp -f build/test_host32s /tmp/rt_test_host32s
    chmod +x /tmp/rt_test_host32s
    run_one() {
        cpu=$1
        echo "======== qemu-i386 -cpu $cpu ========"
        qemu-i386 -cpu "$cpu" /tmp/rt_test_host32s
    }
    case "$target" in
    pentium3|p3) run_one pentium3 ;;
    pentium2|p2) run_one pentium2 ;;
    all) run_one pentium2; echo; run_one pentium3 ;;
    native|host) sh scripts/run.sh ;;
    *) echo "usage: $0 {pentium3|pentium2|all|native}" >&2; exit 1 ;;
    esac
}

# ---------- macOS / ARM: system VM with Alpine ----------
# Uses qemu-system-x86_64 (Homebrew qemu) + Alpine virt ISO.
# First run downloads ~60MB ISO into verify/.cache/
macos_system_vm() {
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo "qemu-system-x86_64 not found. Install: brew install qemu" >&2
        exit 1
    fi

    cache="$(pwd)/verify/.cache"
    mkdir -p "$cache"
    # Alpine virt x86_64 — small, has apk + build tools available after setup
    ALPINE_VER="3.21.3"
    ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-${ALPINE_VER}-x86_64.iso"
    ISO="$cache/alpine-virt-x86_64.iso"
    DISK="$cache/rt-alpine.qcow2"
    SEED="$cache/seed.iso"

    if [ ! -f "$ISO" ]; then
        echo "Downloading Alpine virt ISO (~60MB) to $ISO ..."
        if command -v curl >/dev/null 2>&1; then
            curl -L --fail -o "$ISO.partial" "$ISO_URL"
            mv "$ISO.partial" "$ISO"
        else
            echo "curl required to download Alpine ISO" >&2
            exit 1
        fi
    fi

    if [ ! -f "$DISK" ]; then
        echo "Creating 2G disk image $DISK ..."
        qemu-img create -f qcow2 "$DISK" 2G
        echo ""
        echo "First boot is interactive (one-time Alpine install):"
        echo "  1) login: root (no password)"
        echo "  2) setup-alpine  (defaults OK; set disk mode 'sys' on vda)"
        echo "  3) after reboot: apk add build-base"
        echo "  4) mount -t 9p -o trans=virtio rt /mnt"
        echo "  5) cd /mnt && sh scripts/qemu.sh pentium3"
        echo ""
        echo "Starting installer VM (Ctrl-A X to exit qemu)..."
        exec qemu-system-x86_64 \
            -machine q35 -m 1024 -smp 2 \
            -drive file="$DISK",if=virtio \
            -cdrom "$ISO" -boot d \
            -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
            -fsdev local,id=rt,path="$(pwd)",security_model=none \
            -device virtio-9p-pci,fsdev=rt,mount_tag=rt \
            -nographic
    fi

    echo "Booting Alpine disk with rt/ shared as 9p tag 'rt'..."
    echo "  mount -t 9p -o trans=virtio rt /mnt"
    echo "  cd /mnt && sh scripts/qemu.sh $target"
    exec qemu-system-x86_64 \
        -machine q35 -m 1024 -smp 2 \
        -drive file="$DISK",if=virtio \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
        -fsdev local,id=rt,path="$(pwd)",security_model=none \
        -device virtio-9p-pci,fsdev=rt,mount_tag=rt \
        -nographic
}

case "$host_os:$host_arch" in
Linux:x86_64|Linux:amd64|Linux:i386|Linux:i686)
    linux_usermode
    ;;
Darwin:arm64|Darwin:aarch64)
    macos_system_vm
    ;;
Darwin:x86_64)
    # Intel Mac: prefer user-mode if present, else system VM
    if command -v qemu-i386 >/dev/null 2>&1; then
        linux_usermode
    else
        macos_system_vm
    fi
    ;;
*)
    echo "Unsupported host $host_os $host_arch for qemu profiles." >&2
    exit 1
    ;;
esac
