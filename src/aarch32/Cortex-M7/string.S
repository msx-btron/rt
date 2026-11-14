/* ARMv7E-M strings. Same Thumb-2 integer routines as Cortex-M3.
   strlen: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/strlen-thumb2-Os.S
   Index: third_party/aarch32/SOURCES.md */
.syntax unified
.cpu cortex-m7
.thumb
#define RT_SUF m7
#include "../thumb2/string.inc"
