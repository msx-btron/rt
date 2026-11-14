# BSD make (macOS) and GNU make.
.PHONY: all test test32 qemu qemu-p2 qemu-p3 avx512 riscv clean

all: test

test:
	sh ../scripts/run.sh

test32:
	sh ../scripts/run.sh test32

qemu:
	sh ../scripts/qemu.sh all

qemu-p3:
	sh ../scripts/qemu.sh pentium3

qemu-p2:
	sh ../scripts/qemu.sh pentium2

avx512:
	sh ../scripts/avx512.sh

riscv:
	sh ../scripts/riscv.sh

clean:
	rm -rf ../build
