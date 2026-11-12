#include "rt/stdlib.h"
#include "rt/string.h"
#include "rt/mem.h"

#include <stdint.h>
#include <limits.h>

int rt_abs(int x)
{
    return x < 0 ? -x : x;
}

long rt_labs(long x)
{
    return x < 0 ? -x : x;
}

static int dig(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'z') return c - 'a' + 10;
    if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
    return -1;
}

static unsigned long long parse_u(const char *s, char **end, int base, int *neg)
{
    const char *p = s;
    unsigned long long acc = 0;
    int any = 0;
    *neg = 0;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == '\f' || *p == '\v')
        p++;
    if (*p == '+' || *p == '-') {
        if (*p == '-') *neg = 1;
        p++;
    }
    if (base == 0) {
        if (*p == '0') {
            if (p[1] == 'x' || p[1] == 'X') {
                base = 16;
                p += 2;
            } else {
                base = 8;
                p++;
                any = 1;
            }
        } else {
            base = 10;
        }
    } else if (base == 16 && *p == '0' && (p[1] == 'x' || p[1] == 'X')) {
        p += 2;
    }
    if (base < 2 || base > 36) {
        if (end) *end = (char *)s;
        return 0;
    }
    for (;;) {
        int d = dig(*p);
        if (d < 0 || d >= base) break;
        acc = acc * (unsigned)base + (unsigned)d;
        p++;
        any = 1;
    }
    if (end) *end = (char *)(any ? p : s);
    return acc;
}

int rt_atoi(const char *s)
{
    char *end;
    int neg = 0;
    unsigned long long v = parse_u(s, &end, 10, &neg);
    if (neg) return -(int)v;
    return (int)v;
}

unsigned long rt_strtoul(const char *s, char **end, int base)
{
    int neg = 0;
    unsigned long long v = parse_u(s, end, base, &neg);
    if (neg) return (unsigned long)(0UL - (unsigned long)v);
    return (unsigned long)v;
}

unsigned long long rt_strtoull(const char *s, char **end, int base)
{
    int neg = 0;
    unsigned long long v = parse_u(s, end, base, &neg);
    if (neg) return 0ULL - v;
    return v;
}

long rt_strtol(const char *s, char **end, int base)
{
    int neg = 0;
    unsigned long long v = parse_u(s, end, base, &neg);
    if (neg) return -(long)v;
    return (long)v;
}

long long rt_strtoll(const char *s, char **end, int base)
{
    int neg = 0;
    unsigned long long v = parse_u(s, end, base, &neg);
    if (neg) return -(long long)v;
    return (long long)v;
}

/* Ciura shell sort — fixed gap table, O(1) stack (rt.btron.pro).
   Uses a 256-byte stack temp when size fits; otherwise swaps by rotating
   one element through a single-byte shift (still O(1) stack). */
static const size_t ciura[] = { 701, 301, 132, 57, 23, 10, 4, 1 };

static void el_copy(unsigned char *d, const unsigned char *s, size_t n)
{
    size_t k;
    for (k = 0; k < n; k++)
        d[k] = s[k];
}

void rt_qsort(void *base, size_t nmemb, size_t size,
              int (*cmp)(const void *, const void *))
{
    unsigned char *b = (unsigned char *)base;
    unsigned char tmp[256];
    size_t i, j, gi;
    int use_tmp = size <= sizeof tmp;

    if (nmemb < 2 || size == 0)
        return;

    for (gi = 0; gi < sizeof ciura / sizeof ciura[0]; gi++) {
        size_t gap = ciura[gi];
        if (gap >= nmemb)
            continue;
        for (i = gap; i < nmemb; i++) {
            if (use_tmp) {
                el_copy(tmp, b + i * size, size);
                j = i;
                while (j >= gap && cmp(b + (j - gap) * size, tmp) > 0) {
                    el_copy(b + j * size, b + (j - gap) * size, size);
                    j -= gap;
                }
                el_copy(b + j * size, tmp, size);
            } else {
                /* Rotate element i down the gap chain using one-byte temp. */
                j = i;
                while (j >= gap && cmp(b + (j - gap) * size, b + j * size) > 0) {
                    size_t k;
                    for (k = 0; k < size; k++) {
                        unsigned char c = b[j * size + k];
                        b[j * size + k] = b[(j - gap) * size + k];
                        b[(j - gap) * size + k] = c;
                    }
                    j -= gap;
                }
            }
        }
    }
}

/* ---- optional first-fit pool ---- */
enum { HDR = 8 }; /* size_t size | 1=free */

static unsigned char *g_pool;
static size_t g_pool_sz;

void rt_alloc_init(void *pool, size_t bytes)
{
    size_t *h;
    g_pool = (unsigned char *)pool;
    g_pool_sz = bytes;
    if (!g_pool || bytes < HDR + HDR)
        return;
    h = (size_t *)g_pool;
    h[0] = (bytes - HDR) | 1u; /* free block covering the pool */
}

static size_t blk_size(size_t *h) { return h[0] & ~(size_t)1; }
static int blk_free(size_t *h) { return (int)(h[0] & 1u); }

void *rt_malloc(size_t n)
{
    unsigned char *p;
    size_t need, *h;
    if (!g_pool || n == 0)
        return 0;
    need = (n + sizeof(size_t) - 1) & ~(sizeof(size_t) - 1);
    if (need < sizeof(size_t)) need = sizeof(size_t);
    p = g_pool;
    while (p + HDR <= g_pool + g_pool_sz) {
        h = (size_t *)p;
        if (blk_free(h) && blk_size(h) >= need) {
            size_t rest = blk_size(h) - need;
            if (rest >= HDR + sizeof(size_t)) {
                size_t *nH = (size_t *)(p + HDR + need);
                nH[0] = rest | 1u;
                h[0] = need; /* allocated */
            } else {
                h[0] = blk_size(h); /* consume whole */
            }
            return p + HDR;
        }
        p += HDR + blk_size(h);
    }
    return 0;
}

void rt_free(void *ptr)
{
    size_t *h;
    if (!ptr || !g_pool)
        return;
    h = (size_t *)((unsigned char *)ptr - HDR);
    h[0] |= 1u;
    /* greedy coalesce forward */
    {
        unsigned char *p = (unsigned char *)h;
        size_t *next;
        for (;;) {
            next = (size_t *)(p + HDR + blk_size((size_t *)p));
            if ((unsigned char *)next + HDR > g_pool + g_pool_sz)
                break;
            if (!blk_free(next))
                break;
            ((size_t *)p)[0] = (blk_size((size_t *)p) + HDR + blk_size(next)) | 1u;
        }
    }
}

void *rt_calloc(size_t nmemb, size_t size)
{
    size_t n;
    void *p;
    if (size && nmemb > (size_t)-1 / size)
        return 0;
    n = nmemb * size;
    p = rt_malloc(n);
    if (p)
        rt_memset_scalar(p, 0, n);
    return p;
}

void *rt_realloc(void *ptr, size_t n)
{
    size_t *h;
    size_t old;
    void *q;
    if (!ptr)
        return rt_malloc(n);
    if (n == 0) {
        rt_free(ptr);
        return 0;
    }
    h = (size_t *)((unsigned char *)ptr - HDR);
    old = blk_size(h);
    if (old >= n)
        return ptr;
    q = rt_malloc(n);
    if (!q)
        return 0;
    rt_memcpy_scalar(q, ptr, old);
    rt_free(ptr);
    return q;
}
