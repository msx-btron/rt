#include "rt/mem.h"
#include <stdint.h>

/* Straight loops. On the host, clang -O2 widens an aligned run of these
   into 64-byte stores. The timed rows are 64-byte aligned. */

void *rt_memcpy_scalar(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    size_t i;

    for (i = 0; i < n; i++)
        d[i] = s[i];
    return dst;
}

void *rt_memmove_scalar(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    size_t i;

    if (d == s || n == 0)
        return dst;
    /* Overlap with dst above src must copy from the top. */
    if (d < s) {
        for (i = 0; i < n; i++)
            d[i] = s[i];
        return dst;
    }
    for (i = n; i > 0; i--)
        d[i - 1] = s[i - 1];
    return dst;
}

void *rt_memset_scalar(void *dst, int c, size_t n)
{
    unsigned char *p = (unsigned char *)dst;
    unsigned char uc = (unsigned char)c;
    size_t i;

    for (i = 0; i < n; i++)
        p[i] = uc;
    return dst;
}

int rt_memcmp_scalar(const void *a, const void *b, size_t n)
{
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;

    /* Word loads through memcpy stay inside n. The difference is still
       the first unsigned byte, in address order. */
    while (n >= 32) {
        uint64_t x0, x1, x2, x3, y0, y1, y2, y3;
        __builtin_memcpy(&x0, x, 8);
        __builtin_memcpy(&y0, y, 8);
        __builtin_memcpy(&x1, x + 8, 8);
        __builtin_memcpy(&y1, y + 8, 8);
        __builtin_memcpy(&x2, x + 16, 8);
        __builtin_memcpy(&y2, y + 16, 8);
        __builtin_memcpy(&x3, x + 24, 8);
        __builtin_memcpy(&y3, y + 24, 8);
        if ((x0 ^ y0) | (x1 ^ y1) | (x2 ^ y2) | (x3 ^ y3))
            break;
        x += 32;
        y += 32;
        n -= 32;
    }
    while (n >= 8) {
        uint64_t xw, yw;
        __builtin_memcpy(&xw, x, 8);
        __builtin_memcpy(&yw, y, 8);
        if (xw != yw)
            break;
        x += 8;
        y += 8;
        n -= 8;
    }
    while (n--) {
        if (*x != *y)
            return (int)*x - (int)*y;
        x++;
        y++;
    }
    return 0;
}
