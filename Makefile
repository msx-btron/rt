# rt — host oracle + optional QEMU vintage profiles
#
# macOS M4:  make          → two tables: scalar, neon
# Linux x86_64: make       → scalar + sse2/avx2/avx512 tables
# Linux + qemu: make qemu  → pentium2 + pentium3 tables
#
.PHONY: all test test32 qemu qemu-p2 qemu-p3 clean

all: test

test:
	$(MAKE) -C verify test

test32:
	$(MAKE) -C verify test32

qemu:
	$(MAKE) -C verify qemu

qemu-p3:
	$(MAKE) -C verify qemu-p3

qemu-p2:
	$(MAKE) -C verify qemu-p2

clean:
	$(MAKE) -C verify clean
