/* ARMv7E-M with PLD. STM32F7 and the M7 core of STM32H7.
   Thirty-two byte LDM plus a prefetch. The M4 object has neither. */
.syntax unified
.cpu cortex-m7
.thumb
#define RT_SUF m7
#define RT_UNALIGNED 1
#define RT_PLD 1
#define RT_WIDE 1
#include "../thumb2/mem.inc"
