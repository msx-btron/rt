/* ARMv7E-M integer. STM32F3, F4, G4, L4, L4+, WB (M4 core), WL,
   and the M4 core of STM32H7. DSP packed arithmetic is not an ordered
   memcmp, so this object uses the same word moves as Cortex-M3. */
.syntax unified
.cpu cortex-m4
.thumb
#define RT_SUF m4
#define RT_UNALIGNED 1
#define RT_PLD 0
#define RT_WIDE 0
#include "../thumb2/mem.inc"
