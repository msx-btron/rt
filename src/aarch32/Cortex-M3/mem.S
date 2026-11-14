/* ARMv7-M integer. STM32F1, F2, L1. Unaligned LDR is legal when
   CCR.UNALIGN_TRP is clear, which is the reset value. LDM stays aligned. */
.syntax unified
.cpu cortex-m3
.thumb
#define RT_SUF m3
#define RT_UNALIGNED 1
#define RT_PLD 0
#define RT_WIDE 0
#include "../thumb2/mem.inc"
