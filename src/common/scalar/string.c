#include "rt/string.h"

size_t rt_strlen(const char *s)
{
    const char *p = s;
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
    char *d = dst;
    while (*d)
        d++;
    while ((*d++ = *src++) != '\0')
        ;
    return dst;
}

char *rt_strncat(char *dst, const char *src, size_t n)
{
    char *d = dst;
    size_t i = 0;
    while (*d)
        d++;
    while (i < n && src[i] != '\0') {
        d[i] = src[i];
        i++;
    }
    d[i] = '\0';
    return dst;
}

int rt_strcmp(const char *a, const char *b)
{
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
    size_t i;
    if (*needle == '\0')
        return (char *)hay;
    nlen = rt_strlen(needle);
    while (*hay) {
        if (*hay == *needle) {
            for (i = 0; i < nlen; i++) {
                if (hay[i] != needle[i])
                    break;
            }
            if (i == nlen)
                return (char *)hay;
        }
        hay++;
    }
    return 0;
}

char *rt_strpbrk(const char *s, const char *accept)
{
    const char *a;
    for (; *s; s++) {
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
    size_t dlen = rt_strnlen(dst, n);
    size_t i = 0;
    if (dlen >= n)
        return n + rt_strlen(src);
    while (dlen + i + 1 < n && src[i] != '\0') {
        dst[dlen + i] = src[i];
        i++;
    }
    if (dlen + i < n)
        dst[dlen + i] = '\0';
    while (src[i] != '\0')
        i++;
    return dlen + i;
}

void rt_strpad(char *dst, const char *src, size_t width, int fill)
{
    size_t i = 0;
    unsigned char f = (unsigned char)fill;
    while (i < width && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    while (i < width) {
        dst[i] = (char)f;
        i++;
    }
}
