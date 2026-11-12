#include "rt/mem.h"
#include <stdint.h>

/* ---- memcpy: T-Kernel style 64-byte unroll when 8-aligned relative ---- */
void *rt_memcpy_scalar(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;

    if (n >= 16 && ((((uintptr_t)d ^ (uintptr_t)s) & 7) == 0)) {
        while (((uintptr_t)d & 7) && n) {
            *d++ = *s++;
            n--;
        }
        {
            uint64_t *d64 = (uint64_t *)(void *)d;
            const uint64_t *s64 = (const uint64_t *)(const void *)s;
            while (n >= 64) {
                d64[0] = s64[0];
                d64[1] = s64[1];
                d64[2] = s64[2];
                d64[3] = s64[3];
                d64[4] = s64[4];
                d64[5] = s64[5];
                d64[6] = s64[6];
                d64[7] = s64[7];
                d64 += 8;
                s64 += 8;
                n -= 64;
            }
            while (n >= 8) {
                *d64++ = *s64++;
                n -= 8;
            }
            d = (unsigned char *)d64;
            s = (const unsigned char *)s64;
        }
    } else if (n >= 8 && ((((uintptr_t)d ^ (uintptr_t)s) & 3) == 0)) {
        while (((uintptr_t)d & 3) && n) {
            *d++ = *s++;
            n--;
        }
        {
            uint32_t *d32 = (uint32_t *)(void *)d;
            const uint32_t *s32 = (const uint32_t *)(const void *)s;
            while (n >= 16) {
                d32[0] = s32[0];
                d32[1] = s32[1];
                d32[2] = s32[2];
                d32[3] = s32[3];
                d32 += 4;
                s32 += 4;
                n -= 16;
            }
            while (n >= 4) {
                *d32++ = *s32++;
                n -= 4;
            }
            d = (unsigned char *)d32;
            s = (const unsigned char *)s32;
        }
    }
    while (n--)
        *d++ = *s++;
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

    /* copy backwards */
    d += n;
    s += n;
    if (n >= 16 && ((((uintptr_t)d ^ (uintptr_t)s) & 7) == 0)) {
        while (((uintptr_t)d & 7) && n) {
            *--d = *--s;
            n--;
        }
        {
            uint64_t *d64 = (uint64_t *)(void *)d;
            const uint64_t *s64 = (const uint64_t *)(const void *)s;
            while (n >= 64) {
                d64 -= 8;
                s64 -= 8;
                d64[7] = s64[7];
                d64[6] = s64[6];
                d64[5] = s64[5];
                d64[4] = s64[4];
                d64[3] = s64[3];
                d64[2] = s64[2];
                d64[1] = s64[1];
                d64[0] = s64[0];
                n -= 64;
            }
            while (n >= 8) {
                *--d64 = *--s64;
                n -= 8;
            }
            d = (unsigned char *)d64;
            s = (const unsigned char *)s64;
        }
    }
    while (n--)
        *--d = *--s;
    return dst;
}

void *rt_memset_scalar(void *dst, int c, size_t n)
{
    unsigned char *p = (unsigned char *)dst;
    unsigned char uc = (unsigned char)c;

    if (n >= 16) {
        while (((uintptr_t)p & 7) && n) {
            *p++ = uc;
            n--;
        }
        {
            uint64_t val64 = uc;
            val64 |= val64 << 8;
            val64 |= val64 << 16;
            val64 |= val64 << 32;
            {
                uint64_t *p64 = (uint64_t *)(void *)p;
                while (n >= 64) {
                    p64[0] = val64;
                    p64[1] = val64;
                    p64[2] = val64;
                    p64[3] = val64;
                    p64[4] = val64;
                    p64[5] = val64;
                    p64[6] = val64;
                    p64[7] = val64;
                    p64 += 8;
                    n -= 64;
                }
                while (n >= 8) {
                    *p64++ = val64;
                    n -= 8;
                }
                p = (unsigned char *)p64;
            }
        }
    }
    while (n--)
        *p++ = uc;
    return dst;
}

int rt_memcmp_scalar(const void *a, const void *b, size_t n)
{
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;

    if (n >= 16 && ((((uintptr_t)x ^ (uintptr_t)y) & 7) == 0)) {
        while (((uintptr_t)x & 7) && n) {
            if (*x != *y)
                return (int)*x - (int)*y;
            x++;
            y++;
            n--;
        }
        {
            const uint64_t *x64 = (const uint64_t *)(const void *)x;
            const uint64_t *y64 = (const uint64_t *)(const void *)y;
            while (n >= 8) {
                if (*x64 != *y64)
                    break;
                x64++;
                y64++;
                n -= 8;
            }
            x = (const unsigned char *)x64;
            y = (const unsigned char *)y64;
        }
    }
    while (n--) {
        if (*x != *y)
            return (int)*x - (int)*y;
        x++;
        y++;
    }
    return 0;
}
