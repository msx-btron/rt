#include "rt/mem.h"

#include <stdint.h>

static size_t load_word(const unsigned char *p)
{
    size_t w = 0;
    unsigned b;
    for (b = 0; b < sizeof(size_t); b++)
        w |= (size_t)p[b] << (b * 8);
    return w;
}

static void store_word(unsigned char *p, size_t w)
{
    unsigned b;
    for (b = 0; b < sizeof(size_t); b++)
        p[b] = (unsigned char)(w >> (b * 8));
}

void *rt_memcpy_scalar(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    size_t i = 0;

    while (i < n && ((uintptr_t)(d + i) & (sizeof(size_t) - 1)) != 0) {
        d[i] = s[i];
        i++;
    }
    while (i + sizeof(size_t) <= n) {
        store_word(d + i, load_word(s + i));
        i += sizeof(size_t);
    }
    while (i < n) {
        d[i] = s[i];
        i++;
    }
    return dst;
}

void *rt_memmove_scalar(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;

    if (d == s || n == 0)
        return dst;
    if (d < s)
        return rt_memcpy_scalar(dst, src, n);

    /* Copy backward for overlapping regions. */
    while (n--)
        d[n] = s[n];
    return dst;
}

void *rt_memset_scalar(void *dst, int c, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    unsigned char uc = (unsigned char)c;
    size_t w = 0;
    size_t i = 0;
    unsigned b;

    for (b = 0; b < sizeof(size_t); b++)
        w |= (size_t)uc << (b * 8);

    while (i < n && ((uintptr_t)(d + i) & (sizeof(size_t) - 1)) != 0) {
        d[i] = uc;
        i++;
    }
    while (i + sizeof(size_t) <= n) {
        store_word(d + i, w);
        i += sizeof(size_t);
    }
    while (i < n) {
        d[i] = uc;
        i++;
    }
    return dst;
}

int rt_memcmp_scalar(const void *a, const void *b, size_t n)
{
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;
    size_t i = 0;

    while (i + sizeof(size_t) <= n) {
        if (load_word(x + i) != load_word(y + i))
            break;
        i += sizeof(size_t);
    }
    while (i < n) {
        if (x[i] != y[i])
            return (int)x[i] - (int)y[i];
        i++;
    }
    return 0;
}
