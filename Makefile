# rt — host oracle + optional QEMU vintage profiles
#
# macOS M4:  make          → scalar (vectorize off), scalar (vectorize on),
#                            neon, sme. Each table is its own binary.
# Linux x86_64: make       → scalar off, scalar on, sse2/avx/avx2/avx512
# Linux + qemu: make qemu  → pentium2 + pentium3 tables
# make avx512              → IA-32 and EM64T Alpine images, each ≤50MB
# make security            → clang --analyze, flawfinder, cppcheck, ASCII report
# make verify              → coqc verify/models/MemsetNeon.v (rt_memset_neon, n < 2^64)
#
.PHONY: all test test32 qemu qemu-p2 qemu-p3 avx512 clean verify \
	security security-report sec-scalar sec-verify

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

avx512:
	$(MAKE) -C verify avx512

# Coq check. One file: rt_memset_neon for every n below 2^64.
# `coqc` is the compatibility name. Rocq 9.2's compiler is `rocq compile`.
COQC ?= coqc

verify:
	@set -e; \
	if command -v "$(COQC)" >/dev/null 2>&1; then \
	  compiler="$(COQC)"; \
	elif command -v rocq >/dev/null 2>&1; then \
	  compiler="rocq compile"; \
	else \
	  echo "coqc not on PATH"; exit 1; \
	fi; \
	echo "verify: $$compiler verify/models/MemsetNeon.v"; \
	$$compiler verify/models/MemsetNeon.v; \
	echo "verify: rt_memset_neon, n < 2^64 checked"

clean:
	$(MAKE) -C verify clean
	rm -f verify/models/*.vo verify/models/*.vos verify/models/*.vok \
		verify/models/*.glob verify/models/*.vo.aux

# ── Security and quality static analysis ─────────────────────────────────────
# Same tools as bitedits/btron `make security`: clang --analyze, flawfinder
# level 4 and above, cppcheck warning+portability, then the ASCII tree.
# Assembly backends are not C. They are outside this scan.
# A finding fails the recipe. The record is doc/txt/SQCSA.txt.

SEC_CFLAGS = -std=c99 -Wall -Wextra -Wformat=2 -fno-strict-aliasing -fno-builtin
SEC_INCLUDES = -Iinclude

SCALAR_SRCS = \
	src/common/scalar/mem.c \
	src/common/scalar/string.c \
	src/common/scalar/stdio.c \
	src/common/scalar/stdlib.c

VERIFY_SRCS = \
	verify/suite/test_host.c \
	verify/suite/test_mem.c

sec-scalar:
	@echo "=========================================================="
	@echo " sec-scalar: clang --analyze + flawfinder + cppcheck"
	@echo "=========================================================="
	@set -e; \
	command -v clang >/dev/null 2>&1 || { echo "clang not on PATH"; exit 1; }; \
	command -v flawfinder >/dev/null 2>&1 || { echo "flawfinder not on PATH: brew install flawfinder"; exit 1; }; \
	command -v cppcheck >/dev/null 2>&1 || { echo "cppcheck not on PATH: brew install cppcheck"; exit 1; }; \
	log=$$(mktemp); \
	clang --analyze $(SEC_CFLAGS) $(SEC_INCLUDES) \
		-Xanalyzer -analyzer-output=text $(SCALAR_SRCS) >$$log 2>&1; \
	cat $$log; \
	if grep -E 'warning:|error:' $$log >/dev/null; then \
		rm -f $$log; echo "sec-scalar: clang --analyze reported a finding"; exit 1; \
	fi; \
	rm -f $$log; \
	log=$$(mktemp); \
	flawfinder --minlevel=4 --quiet src/common/scalar/ >$$log 2>&1; \
	cat $$log; \
	if grep -E ':[0-9]+:' $$log >/dev/null; then \
		rm -f $$log; echo "sec-scalar: flawfinder level 4+ hit"; exit 1; \
	fi; \
	rm -f $$log; \
	cppcheck -j4 --std=c99 --enable=warning,portability \
		--error-exitcode=1 --quiet $(SEC_INCLUDES) src/common/scalar/

sec-verify:
	@echo "=========================================================="
	@echo " sec-verify: clang --analyze + flawfinder + cppcheck"
	@echo "=========================================================="
	@set -e; \
	command -v clang >/dev/null 2>&1 || { echo "clang not on PATH"; exit 1; }; \
	command -v flawfinder >/dev/null 2>&1 || { echo "flawfinder not on PATH: brew install flawfinder"; exit 1; }; \
	command -v cppcheck >/dev/null 2>&1 || { echo "cppcheck not on PATH: brew install cppcheck"; exit 1; }; \
	log=$$(mktemp); \
	clang --analyze $(SEC_CFLAGS) $(SEC_INCLUDES) \
		-Xanalyzer -analyzer-output=text $(VERIFY_SRCS) >$$log 2>&1; \
	cat $$log; \
	if grep -E 'warning:|error:' $$log >/dev/null; then \
		rm -f $$log; echo "sec-verify: clang --analyze reported a finding"; exit 1; \
	fi; \
	rm -f $$log; \
	log=$$(mktemp); \
	flawfinder --minlevel=4 --quiet $(VERIFY_SRCS) >$$log 2>&1; \
	cat $$log; \
	if grep -E ':[0-9]+:' $$log >/dev/null; then \
		rm -f $$log; echo "sec-verify: flawfinder level 4+ hit"; exit 1; \
	fi; \
	rm -f $$log; \
	cppcheck -j4 --std=c99 --enable=warning,portability \
		--error-exitcode=1 --quiet $(SEC_INCLUDES) $(VERIFY_SRCS)

security-report:
	@python3 scripts/security_report.py

security: sec-scalar sec-verify
	@echo "=========================================================="
	@echo " ALL SECURITY SCANS COMPLETE"
	@echo "=========================================================="
	@python3 scripts/security_report.py
