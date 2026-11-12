#ifndef RT_STDLIB_H
#define RT_STDLIB_H

#include <stddef.h>

/* Numeric conversion, sort, and optional freestanding allocator.
   Matches the tkl_* / I* plane on rt.btron.pro: no locale, no heap
   required for conversion or qsort (Ciura shell, O(1) stack). */

int               rt_atoi(const char *s);
unsigned long     rt_strtoul(const char *s, char **end, int base);
unsigned long long rt_strtoull(const char *s, char **end, int base);
long              rt_strtol(const char *s, char **end, int base);
long long         rt_strtoll(const char *s, char **end, int base);

void              rt_qsort(void *base, size_t nmemb, size_t size,
                           int (*cmp)(const void *, const void *));

int               rt_abs(int x);
long              rt_labs(long x);

/* Optional segregated first-fit pool. Zero cost if never used.
   Call rt_alloc_init(buf, bytes) once; NULL = disabled. */
void              rt_alloc_init(void *pool, size_t bytes);
void             *rt_malloc(size_t n);
void             *rt_calloc(size_t nmemb, size_t size);
void             *rt_realloc(void *p, size_t n);
void              rt_free(void *p);

#endif
