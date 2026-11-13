#ifndef RT_STDLIB_H
#define RT_STDLIB_H

#include <stddef.h>

/* Numeric conversion, sort, and optional freestanding allocator.
   Matches the tkl_* / I* plane on rt.btron.pro: no locale, no heap
   required for conversion or qsort. */

int               rt_atoi(const char *s);
unsigned long     rt_strtoul(const char *s, char **end, int base);
unsigned long long rt_strtoull(const char *s, char **end, int base);
long              rt_strtol(const char *s, char **end, int base);
long long         rt_strtoll(const char *s, char **end, int base);

/* Iterative introsort (no recursion). Explicit stack ≤ 64 frames.
   JPL Power-of-10 friendly: bounded loops, fixed stack, no malloc.
   Aimed at host-libc parity or better on random integer keys. */
void              rt_qsort(void *base, size_t nmemb, size_t size,
                           int (*cmp)(const void *, const void *));

/* Ciura shell sort — O(1) stack, original BTRON/rt plane.
   Kept in the library. The oracle does not time it. */
void              rt_qsort_simple(void *base, size_t nmemb, size_t size,
                                  int (*cmp)(const void *, const void *));

int               rt_abs(int x);
long              rt_labs(long x);

void              rt_alloc_init(void *pool, size_t bytes);
void             *rt_malloc(size_t n);
void             *rt_calloc(size_t nmemb, size_t size);
void             *rt_realloc(void *p, size_t n);
void              rt_free(void *p);

#endif
