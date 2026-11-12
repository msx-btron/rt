#include "rt/string.h"
#include <stdint.h>
#include <stddef.h>

/* Byte-repeat and zero detection in a word (Warren / glibc style). */
#define ONES   ((size_t)-1 / 255)
#define HIS    (ONES * 0x80)
#define haszero(x)  (((x) - ONES) & ~(x) & HIS)

static size_t load_word(const void *p)
{
    size_t w;
    __builtin_memcpy(&w, p, sizeof w);
    return w;
}

size_t rt_strlen(const char *s)
{
    const char *p = s;
    /* align */
    while (((uintptr_t)p & (sizeof(size_t) - 1)) != 0) {
        if (*p == '\0')
            return (size_t)(p - s);
        p++;
    }
    for (;;) {
        size_t w = load_word(p);
        if (haszero(w))
            break;
        p += sizeof(size_t);
    }
    while (*p)
        p++;
    return (size_t)(p - s);
}

size_t rt_strnlen(const char *s, size_t n)
{
    size_t i = 0;
    while (i < n && s[i])
        i++;
    return i;
}

char *rt_strcpy(char *dst, const char *src)
{
    char *d = dst;
    /* bulk when both aligned the same */
    if ((((uintptr_t)d | (uintptr_t)src) & (sizeof(size_t) - 1)) == 0) {
        for (;;) {
            size_t w = load_word(src);
            if (haszero(w))
                break;
            __builtin_memcpy(d, &w, sizeof w);
            d += sizeof(size_t);
            src += sizeof(size_t);
        }
    }
    while ((*d++ = *src++) != '\0')
        ;
    return dst;
}

char *rt_strncpy(char *dst, const char *src, size_t n)
{
    size_t i = 0;
    while (i < n && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    while (i < n) {
        dst[i] = '\0';
        i++;
    }
    return dst;
}

char *rt_strcat(char *dst, const char *src)
{
    return rt_strcpy(dst + rt_strlen(dst), src);
}

char *rt_strncat(char *dst, const char *src, size_t n)
{
    char *d = dst + rt_strlen(dst);
    size_t i = 0;
    while (i < n && src[i] != '\0') {
        d[i] = src[i];
        i++;
    }
    d[i] = '\0';
    return dst;
}

int rt_strcmp(const char *a, const char *b)
{
    if ((((uintptr_t)a | (uintptr_t)b) & (sizeof(size_t) - 1)) == 0) {
        for (;;) {
            size_t wa = load_word(a);
            size_t wb = load_word(b);
            if (wa != wb || haszero(wa))
                break;
            a += sizeof(size_t);
            b += sizeof(size_t);
        }
    }
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

int rt_strncmp(const char *a, const char *b, size_t n)
{
    size_t i = 0;
    if (n == 0)
        return 0;
    while (i < n && a[i] && a[i] == b[i])
        i++;
    if (i == n)
        return 0;
    return (unsigned char)a[i] - (unsigned char)b[i];
}

char *rt_strchr(const char *s, int c)
{
    unsigned char uc = (unsigned char)c;
    size_t needle;

    while (((uintptr_t)s & (sizeof(size_t) - 1)) != 0) {
        if ((unsigned char)*s == uc)
            return (char *)s;
        if (*s == '\0')
            return 0;
        s++;
    }
    needle = ONES * (size_t)uc;
    for (;;) {
        size_t w = load_word(s);
        size_t x = w ^ needle;
        if (haszero(w) || haszero(x))
            break;
        s += sizeof(size_t);
    }
    for (;;) {
        if ((unsigned char)*s == uc)
            return (char *)s;
        if (*s == '\0')
            return 0;
        s++;
    }
}

char *rt_strrchr(const char *s, int c)
{
    unsigned char uc = (unsigned char)c;
    const char *last = 0;
    for (;;) {
        if ((unsigned char)*s == uc)
            last = s;
        if (*s == '\0')
            return (char *)last;
        s++;
    }
}

char *rt_strstr(const char *hay, const char *needle)
{
    size_t nlen;
    if (!needle[0])
        return (char *)hay;
    nlen = rt_strlen(needle);
    for (; *hay; hay++) {
        if (*hay == *needle && rt_strncmp(hay, needle, nlen) == 0)
            return (char *)hay;
    }
    return 0;
}

char *rt_strpbrk(const char *s, const char *accept)
{
    for (; *s; s++) {
        const char *a;
        for (a = accept; *a; a++) {
            if (*s == *a)
                return (char *)s;
        }
    }
    return 0;
}

size_t rt_strscpy(char *dst, const char *src, size_t n)
{
    size_t i = 0;
    if (n == 0)
        return rt_strlen(src);
    while (i + 1 < n && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
    while (src[i] != '\0')
        i++;
    return i;
}

size_t rt_strscat(char *dst, const char *src, size_t n)
{
    size_t used = rt_strnlen(dst, n);
    size_t added;
    if (used >= n)
        return used + rt_strlen(src);
    added = rt_strscpy(dst + used, src, n - used);
    return used + added;
}

void rt_strpad(char *dst, const char *src, size_t width, int fill)
{
    size_t i = 0;
    while (i < width && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    while (i < width) {
        dst[i] = (char)fill;
        i++;
    }
}
