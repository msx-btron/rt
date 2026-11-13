# BSD make (macOS) and GNU make.
.PHONY: all test test32 qemu qemu-p2 qemu-p3 clean

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

clean:
	rm -rf ../build
