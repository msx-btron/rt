# AArch32 libc opponents

These are baselines. They are not RT kernels. `src/aarch32/` names the
same URLs on each stream. One guest links one `memcpy`. `$ make aarch32`
prints picolibc on Cortex-M and Arm Optimized Routines on A-profile,
then one more table for each other imported memcpy (visenri and LLVM
on M0, NuttX and LLVM on M3, M4, M7, and M33). `A32_LIBC` selects one
tree and skips that tail. Each table prints the kernel directory and
the source URL of every linked body. QEMU does not implement DWT
CYCCNT, so those guests time with semihost SYS_ELAPSED and print host
microseconds. virt Cortex-A7 and Cortex-A15 keep the PMU.

## picolibc 1.8.10

BSD notices in each file. `LICENSE` and `COPYING.NEWLIB`.

https://github.com/picolibc/picolibc/tree/1.8.10/newlib/libc/machine/arm

| File | Guests | Symbol |
| --- | --- | --- |
| `memset-thumb.S` | M0 | `memset` |
| `strlen-thumb1-Os.S` | M0 | `strlen` |
| `memcpy-armv7m.S` | M3, M4, M7, M33 | `memcpy` |
| `memset-thumb2.S` | M3, M4, M7, M33 | `memset` |
| `strlen-thumb2-Os.S` | M3, M4, M7, M33 | `strlen` |
| `strcmp.S` plus `strcmp-armv6m.S` / `strcmp-armv7m.S` | M0, and Thumb-2 when `A32_LIBC=pico` | `strcmp` |
| `memcpy.S` | dispatcher only | none on Thumb-1 |
| `strnlen.c` | every guest on the default run | `strnlen` |

`memcpy.S` includes `memcpy-armv7m.S` only for Thumb-2. Thumb-1 falls
through to a C stub, so M0 memcpy stays `N/A` on the default run.
`strcmp.S` is the dispatcher. clang assembles it. The fragments do not
assemble alone: `def_fn` and `S2LO` live in the dispatcher. Cortex-M4
and M7 define `__ARM_FEATURE_SIMD32`, which would include the missing
`strcmp-armv7.S`. The pico pass undefines that macro and uses
`strcmp-armv7m.S`. Generic `memcmp.c` is not imported.

`strnlen.c` is C. No assembly strnlen exists in this tag.

## NuttX `6b31918b429e6b2351bfa03f005704d123cb70e9`

Modified BSD. Mike Smith / rocksoft, Stellaris forum 2008-07-24.

https://github.com/NuttX/nuttx/blob/6b31918b429e6b2351bfa03f005704d123cb70e9/libs/libc/machine/arm/armv7-m/gnu/arch_memcpy.S

That `gnu/` directory contains only `arch_memcpy.S`. It is Thumb-2
(`tbb`, `bfi`, 40-byte `ldmia`/`stmia`). M3, M4, M7, and M33 link it
when `A32_LIBC=nuttx`. Later NuttX armv8-m trees ship the same Mike
Smith body. It is not imported a second time. armv7-a, armv8-r, and
`lib_memcpy.c` are not imported.

## visenri `2dc57cc1d5944f181db11a0491dba5a00f7c350f`

BSD-3-Clause. Copyright (c) 2024 visenri.

https://github.com/visenri/memcpy_armv6m/blob/2dc57cc1d5944f181db11a0491dba5a00f7c350f/memops_opt/memcpy_armv6m.S

Symbol `memcpy_armv6m`. Defaults are the fastest of the three compile-time
variants (mivo0, miwo1, miwo2): `MEMCPY_ARMV6M_MED_SIZE_SPEED` 2 and a
two-word misaligned loop. clang 22 rejects GNU `LOCAL` and a forward
`subs` immediate. `A32_LIBC=visenri` preprocesses with clang and
assembles with `arm-linux-musleabihf-as` or `arm-none-eabi-as`.

## LLVM libc `a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0`

Apache-2.0 WITH LLVM-exception. The upstream is C++.

https://github.com/llvm/llvm-project/blob/a080750a1e8b5b93f7a93dd6df88ce9b1e3a4fe0/libc/src/string/memory_utils/arm/inline_memcpy.h

`driver.cpp` is the wrapper that returns `dst`. The checked-in `.S`
files are clang 22 `-O2 -S` output. M0 is `inline_memcpy_arm_low_end`
(`ldm`/`stm`). `memcpy-mid.S` is the M3 mid-end; the M4 and M33 text
matches it. `memcpy-m7.S` is the same mid-end with `ldr r3, [r1, #64]!`.
`A32_LIBC=llvm-m0` links the M0 file. `A32_LIBC=llvm-mid` links the
mid file on M3, M4, and M33, and the M7 file on M7.

## Arm Optimized Routines v25.01

MIT OR Apache-2.0 WITH LLVM-exception.

https://github.com/ARM-software/optimized-routines/tree/v25.01/string/arm

| File | Build | Symbol |
| --- | --- | --- |
| `memcpy.S` | `-D__ARM_NEON__=1` on a32 | `__memcpy_arm` |
| `memcpy.S` | no `__ARM_NEON__` on ARM1176 | `__memcpy_arm` |
| `memset.S` | Thumb, Cortex-A7 | `__memset_arm` |
| `strcmp.S` | Thumb, Cortex-A7 | `__strcmp_arm` |
| `strlen-armv6t2.S` | Thumb, Cortex-A7 | `__strlen_armv6t2` |

There is no memcmp in this tag. memset, strcmp, and strlen are Thumb-2
and are not linked on ARM1176 or Cortex-M. glibc's armv7 IFUNC selects
this family and is not vendored:

https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/arm/armv7/multiarch/memcpy.S

## Not imported

- Arm Compiler microlib. It is not published.
- Helium white paper AWPR0004. M55 has no libc memcpy, memset, or strlen.
- RT-Thread `rt_memcpy_cm`. The repository is Apache-2.0 and the body is Micrium / uC/OS.

## Not tuned

Import does not change an RT instruction. A beat is one function against
one of these bodies, and only after a counter moves on that silicon.
QEMU virt PMU ticks are not that counter. QEMU 11 DWT and the ARM1176
c15 counter do not advance, so those time cells stay `N/A`.
