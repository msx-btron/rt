# rt — host oracle + optional QEMU vintage profiles
#
# macOS M4:  make          → two tables: scalar, neon
# Linux x86_64: make       → scalar + sse2/avx2/avx512 tables
# Linux + qemu: make qemu  → pentium2 + pentium3 tables
# make security            → clang --analyze, flawfinder, cppcheck, ASCII report
#
.PHONY: all test test32 qemu qemu-p2 qemu-p3 clean \
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

clean:
	$(MAKE) -C verify clean

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
	verify/test_host.c \
	verify/test_mem.c

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
