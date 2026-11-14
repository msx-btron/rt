/* ARMv7-M strings. The integer body is thumb2/string.inc.
   strlen: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/strlen-thumb2-Os.S
   strcmp: https://github.com/picolibc/picolibc/blob/1.8.10/newlib/libc/machine/arm/strcmp-armv7m.S
   Index: third_party/aarch32/SOURCES.md */
.syntax unified
.cpu cortex-m3
.thumb
#define RT_SUF m3
#include "../thumb2/string.inc"
