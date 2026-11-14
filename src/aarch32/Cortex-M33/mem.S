/* ARMv8-M Mainline integer. STM32H5, L5, U5, U3, WBA, C5.
   Optional DSP is not required. The body runs on every M33. */
.syntax unified
.cpu cortex-m33
.thumb
#define RT_SUF m33
#define RT_UNALIGNED 1
#define RT_PLD 0
#define RT_WIDE 0
#include "../thumb2/mem.inc"
