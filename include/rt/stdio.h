#ifndef RT_STDIO_H
#define RT_STDIO_H

#include <stddef.h>
#include <stdarg.h>

/* Bounded C99 formatter. Zero stream heap. No floating-point locale.
   Supported: %% %c %s %d %i %u %o %x %X %p
   Flags: - + space # 0   Width / precision / length: h hh l ll z t */

int  rt_snprintf(char *buf, size_t n, const char *fmt, ...);
int  rt_vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);

/* Deterministic binary32 decimal helper (no double promotion). */
int  rt_fmt_f32(char *buf, size_t n, float x);
int  rt_fmt_f32_into(char *buf, size_t n, float x, int prec);

#endif
