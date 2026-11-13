# CI matrix

GitHub Actions workflow: `.github/workflows/ci.yml`

| Job | Kernels exercised | How |
|-----|-------------------|-----|
| `x86_64-native` | scalar, SSE2, AVX2, AVX-512 | host `test_host` (CPUID gated) |
| `i386-qemu` | scalar, REP, MMX, SSE | `qemu-i386 -cpu pentium2/3` |
| `i386-qemu` (asm) | PC-98 32/16-bit | assemble only |
| `aarch64-neon-qemu` | scalar, NEON mem+string | `qemu-aarch64` |
| `aarch64-sve` | SVE | assemble + best-effort qemu |
| `riscv64-rvv` | RVV64 | assemble + `qemu-riscv64 -cpu rv64,v=true` |
| `riscv32-rvv` | RVV32 | assemble |
| `sqcsa` | scalar C + host oracle | SQCSA Test Suite: `make security` |
| `verify` | `rt_memset_neon` | Coq verify: Rocq 9.2, then `make verify` |

Local equivalents:

```sh
# native
make

# static analysis (scalar C and the host oracle; not the asm backends)
make security

# Rocq 9.2. Ubuntu's apt coq is 8.18 and cannot check this file.
make verify

# i386
sh verify/qemu.sh all          # Linux x86_64 + multilib

# cross NEON (Linux)
aarch64-linux-gnu-gcc … && qemu-aarch64 ./test_host_a64
```
