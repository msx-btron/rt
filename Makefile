# From the unpacked directory: make
# macOS M4 builds scalar + NEON and runs verify/test_mem.c.
# Linux x86-64 builds scalar + SSE2/AVX2/AVX-512 and runs the same suite.
.PHONY: all test test32 clean

all: test

test:
	$(MAKE) -C verify test

test32:
	$(MAKE) -C verify test32

clean:
	$(MAKE) -C verify clean
