#define _POSIX_C_SOURCE 200809L
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif
/* Host libc vs rt — timed ns columns + improvement coefficient + colored groups.
   Untimed checks are the contract a later proof may treat as the spec.
   Each one requires the return value, the bytes that must change, and the
   bytes that must not. memcmp is sign only, on unsigned bytes.
   The strcpy timing column copies a counted buffer. Its checks are strcpy.
*/
#include "rt/mem.h"
#include "rt/string.h"
#include "rt/stdlib.h"
#include "rt/stdio.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdarg.h>
#include <time.h>
#include <limits.h>

/* One binary runs one table. With no RT_TABLE_* macro the binary runs
   every table it was linked with, which is the CI and qemu shape.
   RT_VECTORIZE marks the scalar build whose C was compiled with the
   vectorizers on. The sources are the same either way. */
#if defined(RT_TABLE_SCALAR)
#define RT_RUN_SCALAR 1
#elif defined(RT_TABLE_NEON)
#define RT_RUN_NEON 1
#elif defined(RT_TABLE_SME)
#define RT_RUN_SME 1
#elif defined(RT_TABLE_SIMD)
#define RT_RUN_SIMD 1
#elif defined(RT_TABLE_RVV)
#define RT_RUN_RVV 1
#else
#define RT_RUN_SCALAR 1
#define RT_RUN_NEON 1
#define RT_RUN_SME 1
#define RT_RUN_SIMD 1
#endif

#if defined(__APPLE__)
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <libkern/OSByteOrder.h>
#include <libkern/OSCacheControl.h>
#endif

enum {
    PAD = 64,
    BUF = 8192,
    NAME = 20,
    BACK = 8,
    MAX_ROWS = 96,
    WARM = 16,
    ITER_MEM = 256,
    ITER_STR = 1024,
    ITER_FMT = 128,
    SAMPLES = 21          /* median of this many timed runs */
};

/* ANSI */
#define C_RESET   "\033[0m"
#define C_BOLD    "\033[1m"
#define C_DIM     "\033[2m"
#define C_RED     "\033[31m"
#define C_GREEN   "\033[32m"
#define C_YELLOW  "\033[33m"
#define C_BLUE    "\033[34m"
#define C_MAGENTA "\033[35m"
#define C_CYAN    "\033[36m"
#define C_WHITE   "\033[37m"
#define C_BG_GRP  "\033[44m"

enum group {
    GRP_MEMORY = 0,
    GRP_STRING,
    GRP_NUMERIC,
    GRP_SORT,
    GRP_FORMAT,
    GRP_ALLOC,
    GRP_COUNT
};

static const char *grp_color[GRP_COUNT] = {
    C_CYAN, C_GREEN, C_YELLOW, C_MAGENTA, C_BLUE, C_RED
};

/* 64-byte alignment: PAD is 64, so the timed g_*+PAD pointers stay on a cache line.
   The neon kernels issue ldp/stp of Q registers and do not peel to 16 bytes. */
static unsigned char g_a[BUF] __attribute__((aligned(64)));
static unsigned char g_b[BUF] __attribute__((aligned(64)));
static unsigned char g_c[BUF] __attribute__((aligned(64)));
static uint32_t g_rng = 0xA5A5F00Du;
static int g_color = 1;

static uint32_t rnd(void)
{
    g_rng = g_rng * 1664525u + 1013904223u;
    return g_rng;
}

static void poison(unsigned char *p, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++)
        p[i] = (unsigned char)(0xA5 ^ (unsigned)(i * 17u));
}

static int same_mem(const void *a, const void *b, size_t n)
{
    return n == 0 || memcmp(a, b, n) == 0;
}

static int canary_ok(const unsigned char *p, size_t begin, size_t end)
{
    size_t i;
    if (begin > BUF || end > BUF)
        return 0;
    for (i = 0; i < begin; i++) {
        if (p[i] != (unsigned char)(0xA5 ^ (unsigned)(i * 17u)))
            return 0;
    }
    for (i = end; i < BUF; i++) {
        if (p[i] != (unsigned char)(0xA5 ^ (unsigned)(i * 17u)))
            return 0;
    }
    return 1;
}

static int sign_eq(int x, int y)
{
    return (x < 0) == (y < 0) && (x > 0) == (y > 0) && (x == 0) == (y == 0);
}

/* high-res monotonic ns */
static uint64_t now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static int cmp_u64(const void *a, const void *b)
{
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return (x > y) - (x < y);
}

static uint64_t median_u64(uint64_t *v, int n)
{
    qsort(v, (size_t)n, sizeof *v, cmp_u64);
    return v[n / 2];
}

struct row {
    char name[NAME];
    char backend[BACK];
    int group;
    unsigned checks;
    unsigned fails;
    uint64_t libc_ns; /* total measured wall for libc path */
    uint64_t rt_ns;   /* total measured wall for rt path */
    int no_libc;      /* host libc has no symbol; libc ns and coef are N/A */
};

static struct row g_rows[MAX_ROWS];
static int g_nrows;

static struct row *row_begin(const char *name, const char *backend, int group)
{
    struct row *r;
    if (g_nrows >= MAX_ROWS)
        return 0;
    r = &g_rows[g_nrows++];
    memset(r, 0, sizeof *r);
    snprintf(r->name, sizeof r->name, "%s", name);
    snprintf(r->backend, sizeof r->backend, "%s", backend);
    r->group = group;
    return r;
}

static void row_add(struct row *r, int ok)
{
    if (!r) return;
    r->checks++;
    if (!ok) r->fails++;
}

/* improvement: libc_ns / rt_ns ; >1 means rt faster */
static double coef(const struct row *r)
{
    if (r->rt_ns == 0)
        return r->libc_ns == 0 ? 1.0 : 99.0;
    return (double)r->libc_ns / (double)r->rt_ns;
}

/* A row is printed only in the table of the backend that owns the function.
   Numeric, sort, format, and alloc are scalar, so they stay on that table.
   A missing body is not a row. */
static int row_in_backend_table(const struct row *r, const char *backend)
{
    return strcmp(r->backend, backend) == 0;
}

static void print_one_backend(const char *backend)
{
    int i, g;
    unsigned tc = 0, tf = 0;
    int any = 0;

    for (i = 0; i < g_nrows; i++) {
        if (row_in_backend_table(&g_rows[i], backend)) {
            any = 1;
            break;
        }
    }
    if (!any)
        return;

    if (g_color)
        printf("\n%s%s══ backend: %-8s ══%s\n", C_BOLD, C_WHITE, backend, C_RESET);
    else
        printf("\n== backend: %s ==\n", backend);

    printf("+------------------+----------+----------+--------+------+------------+\n");
    printf("| function         | libc ns  | rt ns    | checks | fail | coef       |\n");
    printf("+------------------+----------+----------+--------+------+------------+\n");

    for (g = 0; g < GRP_COUNT; g++) {
        int has = 0;
        for (i = 0; i < g_nrows; i++) {
            if (row_in_backend_table(&g_rows[i], backend) && g_rows[i].group == g) {
                has = 1;
                break;
            }
        }
        if (!has)
            continue;

        for (i = 0; i < g_nrows; i++) {
            struct row *r = &g_rows[i];
            const char *st_col, *coef_col, *name_col;
            char libc_s[16];
            char coef_s[16];
            if (!row_in_backend_table(r, backend) || r->group != g)
                continue;
            name_col = g_color ? grp_color[g] : "";
            st_col = r->fails ? (g_color ? C_RED : "") : (g_color ? C_GREEN : "");
            if (r->no_libc) {
                snprintf(libc_s, sizeof libc_s, "N/A");
                snprintf(coef_s, sizeof coef_s, "N/A");
                coef_col = "";
            } else {
                double c = coef(r);
                snprintf(libc_s, sizeof libc_s, "%llu",
                         (unsigned long long)r->libc_ns);
                snprintf(coef_s, sizeof coef_s, "%.2f", c);
                if (c >= 1.05)
                    coef_col = g_color ? C_GREEN : "";
                else if (c <= 0.95)
                    coef_col = g_color ? C_RED : "";
                else
                    coef_col = g_color ? C_YELLOW : "";
            }

            printf("| %s%-16s%s | %8s | %8llu | %6u | %s%4u%s | %s%8s%s |\n",
                   name_col, r->name, g_color ? C_RESET : "",
                   libc_s,
                   (unsigned long long)r->rt_ns,
                   r->checks,
                   st_col, r->fails, g_color ? C_RESET : "",
                   coef_col, coef_s, g_color ? C_RESET : "");
            tc += r->checks;
            tf += r->fails;
        }
    }

    printf("+------------------+----------+----------+--------+------+------------+\n");
    printf("| TOTAL            |          |          | %6u | %s%4u%s |            |\n",
           tc,
           tf ? (g_color ? C_RED : "") : (g_color ? C_GREEN : ""),
           tf, g_color ? C_RESET : "");
    printf("+------------------+----------+----------+--------+------+------------+\n");
}

static void print_report(void)
{
    /* Emit one table per backend, in first-seen order. */
    char seen[16][BACK];
    int nseen = 0;
    int i, j;

    printf("\n");
    if (g_color)
        printf("%srt host oracle%s — one table per accessible backend\n", C_BOLD, C_RESET);
    else
        printf("rt host oracle — one table per accessible backend\n");
    printf("%slegend%s: coef = libc_ns/rt_ns · median of %d samples · 1.00 = parity · N/A = no libc symbol\n",
           g_color ? C_DIM : "", g_color ? C_RESET : "", SAMPLES);

    for (i = 0; i < g_nrows; i++) {
        int found = 0;
        for (j = 0; j < nseen; j++) {
            if (strcmp(seen[j], g_rows[i].backend) == 0) {
                found = 1;
                break;
            }
        }
        if (!found && nseen < 16) {
            snprintf(seen[nseen], BACK, "%s", g_rows[i].backend);
            nseen++;
        }
    }

    for (j = 0; j < nseen; j++)
        print_one_backend(seen[j]);

    printf("\n");
}

/* ===================== MEMORY timed ===================== */

typedef void *(*copy_fn)(void *, const void *, size_t);
typedef void *(*set_fn)(void *, int, size_t);
typedef int (*cmp_fn)(const void *, const void *, size_t);

/* Darwin scalar table. These are the on-disk integer leaves, not the live
   NEON _platform_* bodies. memcmp and the string symbols are NEON even in
   that dylib, so those rows keep the live entry. */
static set_fn g_apple_scalar_memset;
static copy_fn g_apple_scalar_memmove;

static void bench_memcpy(struct row *r, copy_fn libc_fn, copy_fn rt_fn)
{
    enum { N = 4096, LOOPS = ITER_MEM };
    unsigned char *dst = g_a + PAD;
    unsigned char *src = g_b + PAD;
    size_t i, k;
    uint64_t t0, t1;
    static const size_t lens[] = {
        0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33,
        63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512,
        1000, 4096
    };

    /* correctness sweep (untimed): return, bytes, both canaries, source intact */
    {
        size_t li, da, sa;
        for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
            size_t n = lens[li];
            size_t da_step = n < 64 ? 1 : 8;
            size_t sa_step = n < 64 ? 1 : 8;
            for (da = 0; da <= 32; da += da_step) {
                for (sa = 0; sa <= 16; sa += sa_step) {
                    unsigned char *d = g_a + PAD + da;
                    unsigned char *s = g_b + PAD + sa;
                    unsigned char *o = g_c + PAD + da;
                    void *ret;
                    if (PAD + da + n + 8 >= BUF || PAD + sa + n + 8 >= BUF) {
                        row_add(r, 0);
                        continue;
                    }
                    poison(g_a, BUF);
                    poison(g_b, BUF);
                    poison(g_c, BUF);
                    for (i = 0; i < n; i++)
                        s[i] = (unsigned char)(0x5A ^ (unsigned)(i * 19u));
                    memcpy(o, s, n);
                    ret = rt_fn(d, s, n);
                    row_add(r, ret == d);
                    row_add(r, same_mem(d, o, n));
                    row_add(r, canary_ok(g_a, (size_t)(d - g_a), (size_t)(d - g_a) + n));
                    row_add(r, canary_ok(g_b, (size_t)(s - g_b), (size_t)(s - g_b) + n)
                            && same_mem(s, o, n));
                }
            }
        }
    }

    for (i = 0; i < N; i++)
        src[i] = (unsigned char)(rnd() & 0xFFu);

    if (!libc_fn)
        libc_fn = memcpy;
    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            libc_fn(dst, src, N);
            rt_fn(dst, src, N);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                libc_fn(dst, src, N);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                rt_fn(dst, src, N);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
}

static void bench_memmove(struct row *r, copy_fn libc_fn, copy_fn rt_fn)
{
    enum { N = 2048, LOOPS = ITER_MEM };
    unsigned char *base = g_a + PAD;
    size_t i, k;
    uint64_t t0, t1;

    /* Both overlap directions, exact overlap, and a non-overlapping gap.
       The whole buffer must match libc, so a write past the window fails. */
    {
        static const size_t lens[] = {
            0, 1, 2, 3, 4, 7, 8, 15, 16, 17, 31, 32, 33,
            63, 64, 65, 127, 128, 255, 256
        };
        static const size_t offs[] = { 0, 1, 2, 3, 7, 8, 15, 16, 31 };
        size_t li, oi;
        for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
            size_t n = lens[li];
            for (oi = 0; oi < sizeof offs / sizeof offs[0]; oi++) {
                size_t off = offs[oi];
                int above;
                if (PAD + n + off + 8 >= BUF) {
                    row_add(r, 0);
                    continue;
                }
                for (above = 0; above < 2; above++) {
                    unsigned char *win = g_a + PAD;
                    unsigned char *src;
                    unsigned char *dst;
                    void *ret;
                    if (!above && off == 0)
                        continue;
                    poison(g_a, BUF);
                    poison(g_c, BUF);
                    for (i = 0; i < n + off; i++)
                        win[i] = (unsigned char)(0x40 + (unsigned)((i * 3u) & 0xFFu));
                    memcpy(g_c, g_a, BUF);
                    if (above) {
                        dst = win + off;
                        src = win;
                    } else {
                        dst = win;
                        src = win + off;
                    }
                    memmove(g_c + (dst - g_a), g_c + (src - g_a), n);
                    ret = rt_fn(dst, src, n);
                    row_add(r, ret == dst && same_mem(g_a, g_c, BUF));
                }
            }
            if (n < 2000) {
                size_t gap;
                for (gap = 1; gap <= 16; gap += 15) {
                    unsigned char *win = g_a + PAD;
                    unsigned char *src = win;
                    unsigned char *dst = win + n + gap;
                    void *ret;
                    if (PAD + n + gap + n + 8 >= BUF) {
                        row_add(r, 0);
                        continue;
                    }
                    poison(g_a, BUF);
                    poison(g_c, BUF);
                    for (i = 0; i < n + gap + n; i++)
                        win[i] = (unsigned char)(0x20 + (unsigned)(i & 0xFFu));
                    memcpy(g_c, g_a, BUF);
                    memmove(g_c + (dst - g_a), g_c + (src - g_a), n);
                    ret = rt_fn(dst, src, n);
                    row_add(r, ret == dst && same_mem(g_a, g_c, BUF));
                    src = win + n + gap;
                    dst = win;
                    poison(g_a, BUF);
                    poison(g_c, BUF);
                    for (i = 0; i < n + gap + n; i++)
                        win[i] = (unsigned char)(0x21 + (unsigned)(i & 0xFFu));
                    memcpy(g_c, g_a, BUF);
                    memmove(g_c + (dst - g_a), g_c + (src - g_a), n);
                    ret = rt_fn(dst, src, n);
                    row_add(r, ret == dst && same_mem(g_a, g_c, BUF));
                }
            }
        }
    }

    for (i = 0; i < N + 64; i++)
        base[i] = (unsigned char)(rnd() & 0xFFu);

    if (!libc_fn)
        libc_fn = memmove;
    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            libc_fn(base + 16, base, N);
            rt_fn(base + 16, base, N);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                libc_fn(base + 16, base, N);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                rt_fn(base + 16, base, N);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
}

static void bench_memset(struct row *r, set_fn libc_fn, set_fn rt_fn, int split)
{
    enum { N = 4096, LOOPS = ITER_MEM };
    unsigned char *dst = g_a + PAD;
    size_t i, k;
    uint64_t t0, t1;
    set_fn side[2];
    int nsides, s;

    if (!libc_fn)
        libc_fn = memset;
    side[0] = rt_fn;
    nsides = 1;
    /* A substitute libc body is checked too. Live memset is not. */
    if (libc_fn != (set_fn)memset) {
        side[1] = libc_fn;
        nsides = 2;
    }

    for (s = 0; s < nsides; s++) {
        set_fn fn = side[s];
        static const size_t lens[] = {
            0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33,
            63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512,
            1000, 4096
        };
        static const int fills[] = { 0, 1, 0x7F, 0x80, 0xFF, -1, 256 + 65 };
        size_t li, da;
        int fi;
        for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
            size_t n = lens[li];
            size_t da_step = n < 64 ? 1 : 8;
            for (fi = 0; fi < (int)(sizeof fills / sizeof fills[0]); fi++) {
                int c = fills[fi];
                unsigned char uc = (unsigned char)c;
                for (da = 0; da <= 32; da += da_step) {
                    unsigned char *d = g_a + PAD + da;
                    void *ret;
                    int bytes_ok = 1;
                    if (PAD + da + n + 8 >= BUF) {
                        row_add(r, 0);
                        continue;
                    }
                    poison(g_a, BUF);
                    ret = fn(d, c, n);
                    for (i = 0; i < n; i++) {
                        if (d[i] != uc)
                            bytes_ok = 0;
                    }
                    row_add(r, ret == d);
                    row_add(r, bytes_ok);
                    row_add(r, canary_ok(g_a, (size_t)(d - g_a), (size_t)(d - g_a) + n));
                }
            }
        }
    }

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        if (!split) {
            for (k = 0; k < WARM; k++) {
                libc_fn(dst, 0xA5, N);
                rt_fn(dst, 0xA5, N);
            }
            for (si = 0; si < SAMPLES; si++) {
                t0 = now_ns();
                for (k = 0; k < LOOPS; k++)
                    libc_fn(dst, 0xA5, N);
                t1 = now_ns();
                lc[si] = t1 - t0;
                t0 = now_ns();
                for (k = 0; k < LOOPS; k++)
                    rt_fn(dst, 0xA5, N);
                t1 = now_ns();
                rt_t[si] = t1 - t0;
            }
        } else {
            /* Separate the two clocks. smstart/smstop must not tax the other side. */
            for (k = 0; k < WARM; k++)
                libc_fn(dst, 0xA5, N);
            for (si = 0; si < SAMPLES; si++) {
                t0 = now_ns();
                for (k = 0; k < LOOPS; k++)
                    libc_fn(dst, 0xA5, N);
                t1 = now_ns();
                lc[si] = t1 - t0;
            }
            for (k = 0; k < WARM; k++)
                rt_fn(dst, 0xA5, N);
            for (si = 0; si < SAMPLES; si++) {
                t0 = now_ns();
                for (k = 0; k < LOOPS; k++)
                    rt_fn(dst, 0xA5, N);
                t1 = now_ns();
                rt_t[si] = t1 - t0;
            }
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
}

static void bench_memcmp(struct row *r, cmp_fn rt_fn)
{
    enum { N = 4096, LOOPS = ITER_MEM };
    unsigned char *a = g_a + PAD;
    unsigned char *b = g_b + PAD;
    size_t i, k;
    uint64_t t0, t1;
    volatile int sink = 0;

    /* Sign of the unsigned difference, including the high bit. No writes. */
    {
        static const size_t lens[] = {
            0, 1, 2, 3, 4, 7, 8, 15, 16, 17, 31, 32, 63, 64, 65, 127, 128, 255, 256, 4096
        };
        static const unsigned char pairs[][2] = {
            { 0x00, 0x00 },
            { 0x00, 0x01 },
            { 0x01, 0x00 },
            { 0x7F, 0x80 },
            { 0x80, 0x7F },
            { 0xFF, 0x00 },
            { 0x00, 0xFF }
        };
        size_t li, pi, da;
        for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
            size_t n = lens[li];
            for (da = 0; da <= 16; da += (n < 64 ? 1 : 8)) {
                unsigned char *ap = g_a + PAD + da;
                unsigned char *bp = g_b + PAD + da;
                size_t at;
                if (PAD + da + n + 8 >= BUF || n > BUF / 2) {
                    row_add(r, 0);
                    continue;
                }
                poison(g_a, BUF);
                poison(g_b, BUF);
                for (i = 0; i < n; i++)
                    ap[i] = bp[i] = (unsigned char)(0x30 + (i * 13u) % 200u);
                memcpy(g_c, ap, n);
                memcpy(g_c + n, bp, n);
                row_add(r, sign_eq(rt_fn(ap, bp, n), memcmp(ap, bp, n))
                        && same_mem(ap, g_c, n) && same_mem(bp, g_c + n, n)
                        && canary_ok(g_a, PAD + da, PAD + da + n)
                        && canary_ok(g_b, PAD + da, PAD + da + n));
                if (!n)
                    continue;
                for (at = 0; at < n; at += (n > 3 ? n - 1 : 1)) {
                    bp[at] ^= 0xFFu;
                    memcpy(g_c, ap, n);
                    memcpy(g_c + n, bp, n);
                    row_add(r, sign_eq(rt_fn(ap, bp, n), memcmp(ap, bp, n))
                            && same_mem(ap, g_c, n) && same_mem(bp, g_c + n, n));
                    bp[at] ^= 0xFFu;
                }
                for (pi = 0; pi < sizeof pairs / sizeof pairs[0]; pi++) {
                    ap[0] = pairs[pi][0];
                    bp[0] = pairs[pi][1];
                    row_add(r, sign_eq(rt_fn(ap, bp, n), memcmp(ap, bp, n)));
                    ap[n - 1] = pairs[pi][0];
                    bp[n - 1] = pairs[pi][1];
                    ap[0] = (unsigned char)0x30;
                    bp[0] = (unsigned char)0x30;
                    row_add(r, sign_eq(rt_fn(ap, bp, n), memcmp(ap, bp, n)));
                    ap[n - 1] = (unsigned char)(0x30 + ((n - 1) * 13u) % 200u);
                    bp[n - 1] = ap[n - 1];
                }
            }
        }
    }

    for (i = 0; i < N; i++)
        a[i] = b[i] = (unsigned char)(i & 0xFFu);

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            sink += memcmp(a, b, N);
            sink += rt_fn(a, b, N);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink += memcmp(a, b, N);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink += rt_fn(a, b, N);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
    (void)sink;
}

__attribute__((unused))
static void run_mem_backend(const char *backend, copy_fn cpy, copy_fn mv,
                            set_fn set, cmp_fn cmp)
{
    struct row *r;
    copy_fn libc_cpy = memcpy;
    copy_fn libc_mv = memmove;
    set_fn libc_set = memset;

    /* Scalar Apple columns are the mapped integer leaves. Other backends
       keep the live symbols. */
    if (strcmp(backend, "scalar") == 0) {
        if (g_apple_scalar_memmove) {
            libc_cpy = g_apple_scalar_memmove;
            libc_mv = g_apple_scalar_memmove;
        }
        if (g_apple_scalar_memset)
            libc_set = g_apple_scalar_memset;
    }
    if (cpy) {
        r = row_begin("memcpy", backend, GRP_MEMORY);
        if (r) bench_memcpy(r, libc_cpy, cpy);
    }
    if (mv) {
        r = row_begin("memmove", backend, GRP_MEMORY);
        if (r) bench_memmove(r, libc_mv, mv);
    }
    if (set) {
        r = row_begin("memset", backend, GRP_MEMORY);
        if (r) bench_memset(r, libc_set, set, 0);
    }
    if (cmp) {
        r = row_begin("memcmp", backend, GRP_MEMORY);
        if (r) bench_memcmp(r, cmp);
    }
}

/* ===================== STRING timed ===================== */

typedef size_t (*strlen_fn)(const char *);
typedef int (*strcmp_fn)(const char *, const char *);
typedef char *(*strchr_fn)(const char *, int);

/* n matching bytes, then NUL. fill < 0 writes 'a'+i%26; otherwise that byte.
   at in [0, n] replaces one byte (at == n is a prefix: b continues one byte).
   The byte after the NUL differs, so a step past the terminator fails sign_eq.
   Caller provides n + 2 bytes, and 32 bytes of readable tail for the neon load. */
static void strcmp_set(char *a, char *b, int n, int at, int fill, int av, int bv)
{
    int i;
    for (i = 0; i < n; i++) {
        if (fill < 0)
            a[i] = b[i] = (char)('a' + (i % 26));
        else
            a[i] = b[i] = (char)fill;
    }
    a[n] = b[n] = 0;
    a[n + 1] = (char)0x5A;
    b[n + 1] = (char)0xA5;
    if (at >= 0 && at <= n) {
        a[at] = (char)av;
        b[at] = (char)bv;
        if (at == n)
            b[n + 1] = 0;
    }
}

static void bench_strlen_fn(struct row *r, strlen_fn fn)
{
    enum { LOOPS = ITER_STR };
    static char s[1025] __attribute__((aligned(64)));
    size_t i, k;
    uint64_t t0, t1;
    volatile size_t sink = 0;

    for (i = 0; i < 1024; i++)
        s[i] = (char)('a' + (i % 26));
    s[100] = (char)0x80;
    s[101] = (char)0xFF;
    s[1024] = 0;

    /* Length is the first 0 byte. 0x80 and 0xFF are not terminators.
       Offsets catch a word or NEON load that starts only on an alignment. */
    {
        static char buf[8192];
        size_t len, al;
        for (len = 0; len <= 64; len++) {
            for (al = 0; al <= 32; al++) {
                size_t j;
                for (j = 0; j < al + len + 64; j++)
                    buf[j] = (char)(0x41 + (j & 15));
                if (len)
                    buf[al + len - 1] = (char)0xFF;
                buf[al + len] = 0;
                row_add(r, fn(buf + al) == len);
            }
        }
    }
    row_add(r, fn(s) == 1024);
    row_add(r, fn(s + 1) == 1023);
    row_add(r, fn("") == 0);

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            sink += strlen(s);
            sink += fn(s);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink += strlen(s);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink += fn(s);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
    (void)sink;
}

static void bench_strcmp_fn(struct row *r, strcmp_fn fn)
{
    enum { LOOPS = ITER_STR };
    static char a[512] __attribute__((aligned(64)));
    static char b[512] __attribute__((aligned(64)));
    static char raw[1280] __attribute__((aligned(64)));
    size_t i, k;
    uint64_t t0, t1;
    volatile int sink = 0;
    int at, off;

    for (i = 0; i < 255; i++)
        a[i] = b[i] = (char)('a' + (i % 26));
    a[255] = b[255] = 0;
    b[200] = 'z';

    row_add(r, sign_eq(fn(a, b), strcmp(a, b)));
    row_add(r, sign_eq(fn(a, a), 0));
    {
        char e1[1], e2[1], p1[8], p2[8], q1[2], q2[2];
        char h1[2], h2[2];
        e1[0] = 0;
        e2[0] = 0;
        memcpy(p1, "abc", 4);
        memcpy(p2, "abcd", 5);
        q1[0] = 'b';
        q1[1] = 0;
        q2[0] = 'a';
        q2[1] = 0;
        h1[0] = (char)0x80;
        h1[1] = 0;
        h2[0] = (char)0x7F;
        h2[1] = 0;
        row_add(r, sign_eq(fn(e1, e2), strcmp(e1, e2)));
        row_add(r, sign_eq(fn(p1, p2), strcmp(p1, p2)));
        row_add(r, sign_eq(fn(p2, p1), strcmp(p2, p1)));
        row_add(r, sign_eq(fn(q1, q2), strcmp(q1, q2)));
        /* Unsigned char order. A signed subtract gets 0x80 and 0x7F backwards. */
        row_add(r, sign_eq(fn(h1, h2), strcmp(h1, h2)));
        row_add(r, sign_eq(fn(h2, h1), strcmp(h2, h1)));
        h1[0] = (char)0xFF;
        h2[0] = 1;
        row_add(r, sign_eq(fn(h1, h2), strcmp(h1, h2)));
        row_add(r, sign_eq(fn(h2, h1), strcmp(h2, h1)));
    }
    {
        char ua[128], ub[128];
        size_t al;
        for (al = 0; al <= 15; al++) {
            memset(ua, 'a', sizeof ua);
            memset(ub, 'a', sizeof ub);
            ua[al + 20] = 0;
            ub[al + 20] = 0;
            ub[al + 19] = (char)0xFF;
            row_add(r, sign_eq(fn(ua + al, ub + al), strcmp(ua + al, ub + al)));
            row_add(r, sign_eq(fn(ub + al, ua + al), strcmp(ub + al, ua + al)));
        }
    }
    /* Each lane of two 32-byte chunks, then a NUL whose following bytes differ. */
    for (at = 0; at <= 63; at++) {
        strcmp_set(a, b, 96, at, -1, 'a', 'z');
        row_add(r, sign_eq(fn(a, b), strcmp(a, b)));
        row_add(r, sign_eq(fn(b, a), strcmp(b, a)));
        strcmp_set(a, b, at, -1, -1, 0, 0);
        row_add(r, sign_eq(fn(a, b), strcmp(a, b)));
    }
    /* Matched bytes below 16: the index tail must not treat them as a stop. */
    for (at = 0; at <= 48; at++) {
        strcmp_set(a, b, 64, at, 1, 2, 9);
        row_add(r, sign_eq(fn(a, b), strcmp(a, b)));
        row_add(r, sign_eq(fn(b, a), strcmp(b, a)));
    }
    strcmp_set(a, b, 64, 40, 0x80, 0x80, 0x7F);
    row_add(r, sign_eq(fn(a, b), strcmp(a, b)));
    row_add(r, sign_eq(fn(b, a), strcmp(b, a)));
    strcmp_set(a, b, 64, 20, -1, (char)0xFF, 1);
    row_add(r, sign_eq(fn(a, b), strcmp(a, b)));
    row_add(r, sign_eq(fn(b, a), strcmp(b, a)));
    for (off = 0; off <= 15; off++) {
        strcmp_set(raw + off, raw + 640 + off, 100, -1, -1, 0, 0);
        row_add(r, sign_eq(fn(raw + off, raw + 640 + off),
                           strcmp(raw + off, raw + 640 + off)));
        strcmp_set(raw + off, raw + 640 + off, 220, 200, -1, 'a', 'z');
        row_add(r, sign_eq(fn(raw + off, raw + 640 + off),
                           strcmp(raw + off, raw + 640 + off)));
        row_add(r, sign_eq(fn(raw + 640 + off, raw + off),
                           strcmp(raw + 640 + off, raw + off)));
    }
    for (off = 1; off <= 15; off += 7) {
        strcmp_set(a, raw + off, 80, 50, -1, 'a', 'z');
        row_add(r, sign_eq(fn(a, raw + off), strcmp(a, raw + off)));
        row_add(r, sign_eq(fn(raw + off, a), strcmp(raw + off, a)));
        strcmp_set(raw + off, b, 80, 16, -1, 'q', 'a');
        row_add(r, sign_eq(fn(raw + off, b), strcmp(raw + off, b)));
        row_add(r, sign_eq(fn(b, raw + off), strcmp(b, raw + off)));
    }

    for (i = 0; i < 255; i++)
        a[i] = b[i] = (char)('a' + (i % 26));
    a[255] = b[255] = 0;
    b[200] = 'z';

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            sink += strcmp(a, b);
            sink += fn(a, b);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink += strcmp(a, b);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink += fn(a, b);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
    (void)sink;
}

static void bench_strchr_fn(struct row *r, strchr_fn fn)
{
    enum { LOOPS = ITER_STR };
    static char s[512] __attribute__((aligned(64)));
    size_t i, k;
    uint64_t t0, t1;
    volatile uintptr_t sink = 0;

    for (i = 0; i < 511; i++)
        s[i] = (char)('a' + (i % 26));
    s[400] = 'Z';
    s[511] = 0;

    row_add(r, fn(s, 'Z') == strchr(s, 'Z'));
    row_add(r, fn(s, 'Q') == strchr(s, 'Q'));
    row_add(r, fn(s, 0) == strchr(s, 0));
    row_add(r, fn("", 'a') == strchr("", 'a'));
    row_add(r, fn("x", 'x') == strchr("x", 'x'));
    /* c is converted to unsigned char. 256 + 'Z' is the 'Z' at s[400]. */
    row_add(r, fn(s, 256 + 'Z') == s + 400);
    row_add(r, fn(s, 256) == s + 511);
    {
        char hi[32];
        size_t al;
        memset(hi, 'b', sizeof hi);
        hi[31] = 0;
        hi[8] = (char)0xFF;
        row_add(r, fn(hi, 0xFF) == hi + 8);
        row_add(r, fn(hi, 256 + 0xFF) == hi + 8);
        for (al = 0; al <= 15; al++) {
            char buf[64];
            memset(buf, 'c', sizeof buf);
            buf[al + 10] = 'Z';
            buf[al + 24] = 0;
            row_add(r, fn(buf + al, 'Z') == buf + al + 10);
            row_add(r, fn(buf + al, 'Q') == 0);
        }
    }

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            sink ^= (uintptr_t)strchr(s, 'Z');
            sink ^= (uintptr_t)fn(s, 'Z');
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink ^= (uintptr_t)strchr(s, 'Z');
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink ^= (uintptr_t)fn(s, 'Z');
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
    (void)sink;
}


static void bench_strcpy(struct row *r)
{
    enum { LOOPS = ITER_STR, N = 512 };
    static char src[N] __attribute__((aligned(64)));
    static char da[N] __attribute__((aligned(64)));
    static char db[N] __attribute__((aligned(64)));
    size_t i, k, ncopy;
    uint64_t t0, t1;

    for (i = 0; i < N - 1; i++)
        src[i] = (char)('A' + (i % 26));
    src[N - 1] = 0;

    /* The NUL sits in the last byte, so strcpy would write N bytes.
       memcpy of that count is the same write, and the length is checked. */
    ncopy = 0;
    while (ncopy < N && src[ncopy] != '\0')
        ncopy++;
    if (ncopy >= N || ncopy + 1 > sizeof da || ncopy + 1 > sizeof db) {
        row_add(r, 0);
        return;
    }
    ncopy++;

    /* strcpy writes strlen bytes plus the NUL and returns dst.
       Bytes past that NUL stay as they were. */
    {
        char tiny[96];
        size_t len;
        static const size_t lens[] = { 0, 1, 2, 3, 7, 8, 15, 16, 17, 31, 32, 33 };
        for (len = 0; len < sizeof lens / sizeof lens[0]; len++) {
            char raw[96];
            size_t n = lens[len];
            size_t j;
            char *ret;
            for (j = 0; j < n; j++)
                raw[j] = (j == n - 1 && n) ? (char)0xFF : (char)('A' + (j % 26));
            if (n)
                raw[n - 1] = (n > 1) ? (char)0xFF : 'A';
            raw[n] = 0;
            memset(tiny, 0xA5, sizeof tiny);
            memset(da, 0xA5, sizeof da);
            memcpy(da, raw, n + 1);
            ret = rt_strcpy(tiny, raw);
            row_add(r, ret == tiny && memcmp(tiny, da, sizeof tiny) == 0);
        }
        memset(db, 0xA5, sizeof db);
        memset(da, 0xA5, sizeof da);
        memcpy(da, src, ncopy);
        row_add(r, rt_strcpy(db, src) == db && memcmp(db, da, sizeof db) == 0);
    }

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        /* Counted copy of the same bytes strcpy writes. On Darwin this is
           the on-disk integer memmove, not live NEON memcpy. */
        copy_fn libc_fn = g_apple_scalar_memmove ? g_apple_scalar_memmove : memcpy;
        for (k = 0; k < WARM; k++) {
            libc_fn(da, src, ncopy);
            rt_strcpy(db, src);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                libc_fn(da, src, ncopy);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                rt_strcpy(db, src);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
}

static void bench_strstr(struct row *r)
{
    enum { LOOPS = ITER_STR };
    static char hay[1024] __attribute__((aligned(64)));
    static char nd[16] __attribute__((aligned(64))) = "needle";
    size_t i, k;
    uint64_t t0, t1;
    volatile uintptr_t sink = 0;

    for (i = 0; i < 1000; i++)
        hay[i] = (char)('a' + (i % 26));
    memcpy(hay + 500, nd, 6);
    hay[1023] = 0;

    row_add(r, rt_strstr(hay, nd) == strstr(hay, nd));
    row_add(r, rt_strstr(hay, "") == hay);
    row_add(r, rt_strstr(hay, "no-such-needle") == 0);
    {
        const char *at = "needle-at-start";
        row_add(r, rt_strstr(at, "needle") == at);
    }
    row_add(r, rt_strstr("xxneedle", "needle") == strstr("xxneedle", "needle"));
    row_add(r, rt_strstr("aaaab", "aaab") == strstr("aaaab", "aaab"));
    row_add(r, rt_strstr("ababcabcd", "abc") == strstr("ababcabcd", "abc"));
    row_add(r, rt_strstr("", "") == strstr("", ""));
    row_add(r, rt_strstr("", "a") == 0);
    row_add(r, rt_strstr("abc", "abcd") == 0);
    {
        char hi[16];
        memcpy(hi, "a\377b", 4);
        row_add(r, rt_strstr(hi, "\377b") == hi + 1);
    }

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            sink ^= (uintptr_t)strstr(hay, nd);
            sink ^= (uintptr_t)rt_strstr(hay, nd);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink ^= (uintptr_t)strstr(hay, nd);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                sink ^= (uintptr_t)rt_strstr(hay, nd);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
        }
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
    (void)sink;
}

__attribute__((unused))
static void exercise_strings_misc(void)
{
    struct row *r;
    size_t n;

    r = row_begin("strnlen", "scalar", GRP_STRING);
    for (n = 0; n <= 20; n++)
        row_add(r, rt_strnlen("abcdefghijklmnop", n) == (size_t)strnlen("abcdefghijklmnop", n));
    {
        char hi[4];
        hi[0] = 'a';
        hi[1] = (char)0xFF;
        hi[2] = 'b';
        hi[3] = 0;
        row_add(r, rt_strnlen(hi, 10) == 3);
        row_add(r, rt_strnlen(hi, 1) == 1);
        row_add(r, rt_strnlen("", 5) == 0);
        row_add(r, rt_strnlen("abc", 0) == 0);
    }
    /* tiny timing */
    {
        uint64_t t0, t1;
        size_t k;
        volatile size_t sink = 0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += strnlen("abcdefghijklmnop", 8);
        t1 = now_ns();
        if (r) r->libc_ns = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += rt_strnlen("abcdefghijklmnop", 8);
        t1 = now_ns();
        if (r) r->rt_ns = t1 - t0;
        (void)sink;
    }

    r = row_begin("strscpy", "scalar", GRP_STRING);
    {
        const char *src = "abcdefghij";
        size_t srclen = strlen(src);
        for (n = 0; n <= 16; n++) {
            char dst[32];
            size_t got, i, expect;
            int pref = 1, tail = 1;
            memset(dst, 0xCC, 32);
            got = rt_strscpy(dst, src, n);
            row_add(r, got == srclen);
            if (n == 0) {
                for (i = 0; i < 32; i++) {
                    if ((unsigned char)dst[i] != 0xCC)
                        tail = 0;
                }
                row_add(r, tail);
                continue;
            }
            expect = (n - 1) < srclen ? (n - 1) : srclen;
            for (i = 0; i < expect; i++) {
                if (dst[i] != src[i])
                    pref = 0;
            }
            if (dst[expect] != '\0')
                pref = 0;
            for (i = expect + 1; i < 32; i++) {
                if ((unsigned char)dst[i] != 0xCC)
                    tail = 0;
            }
            row_add(r, pref && tail);
        }
        {
            char src2[4];
            char dst[8];
            src2[0] = 'Q';
            src2[1] = (char)0xFF;
            src2[2] = 'Z';
            src2[3] = 0;
            memset(dst, 0xCC, 8);
            row_add(r, rt_strscpy(dst, src2, 8) == 3);
            row_add(r, dst[0] == 'Q' && (unsigned char)dst[1] == 0xFF
                    && dst[2] == 'Z' && dst[3] == '\0'
                    && (unsigned char)dst[4] == 0xCC);
        }
        if (r) {
            /* musl and Apple libc have no strscpy. Time rt. libc and coef are N/A. */
            uint64_t rt_t[SAMPLES];
            int si;
            size_t k;
            uint64_t t0, t1;
            volatile size_t sink = 0;
            char dst[32];
            r->no_libc = 1;
            for (k = 0; k < WARM; k++)
                sink += rt_strscpy(dst, src, 16);
            for (si = 0; si < SAMPLES; si++) {
                t0 = now_ns();
                for (k = 0; k < ITER_STR; k++)
                    sink += rt_strscpy(dst, src, 16);
                t1 = now_ns();
                rt_t[si] = t1 - t0;
            }
            r->rt_ns = median_u64(rt_t, SAMPLES);
            (void)sink;
        }
    }
}

__attribute__((unused))
static void run_strings(void)
{
    struct row *r;
    r = row_begin("strlen", "scalar", GRP_STRING);
    if (r) bench_strlen_fn(r, rt_strlen);
    r = row_begin("strcpy", "scalar", GRP_STRING);
    if (r) bench_strcpy(r);
    r = row_begin("strcmp", "scalar", GRP_STRING);
    if (r) bench_strcmp_fn(r, rt_strcmp);
    r = row_begin("strchr", "scalar", GRP_STRING);
    if (r) bench_strchr_fn(r, rt_strchr);
    r = row_begin("strstr", "scalar", GRP_STRING);
    if (r) bench_strstr(r);
    exercise_strings_misc();
}

#if defined(__riscv) && (defined(RT_RUN_RVV) || defined(RT_RUN_SCALAR))
/* One binary, one backend. The benches are the same for the C99 scalar
   kernels and the RVV kernels so the two tables compare the same calls. */
#if defined(RT_RUN_RVV)
#define RT_STRLEN   rt_strlen_rvv
#define RT_STRNLEN  rt_strnlen_rvv
#define RT_STRCPY   rt_strcpy_rvv
#define RT_STRNCPY  rt_strncpy_rvv
#define RT_STRCAT   rt_strcat_rvv
#define RT_STRNCAT  rt_strncat_rvv
#define RT_STRCMP   rt_strcmp_rvv
#define RT_STRNCMP  rt_strncmp_rvv
#define RT_STRCHR   rt_strchr_rvv
#define RT_STRRCHR  rt_strrchr_rvv
#define RT_STRSTR   rt_strstr_rvv
#define RT_STRPBRK  rt_strpbrk_rvv
#define RT_STRSCPY  rt_strscpy_rvv
#define RT_STRSCAT  rt_strscat_rvv
#define RT_STRPAD   rt_strpad_rvv
#define RT_BACKEND  "rvv"
#else
#define RT_STRLEN   rt_strlen
#define RT_STRNLEN  rt_strnlen
#define RT_STRCPY   rt_strcpy
#define RT_STRNCPY  rt_strncpy
#define RT_STRCAT   rt_strcat
#define RT_STRNCAT  rt_strncat
#define RT_STRCMP   rt_strcmp
#define RT_STRNCMP  rt_strncmp
#define RT_STRCHR   rt_strchr
#define RT_STRRCHR  rt_strrchr
#define RT_STRSTR   rt_strstr
#define RT_STRPBRK  rt_strpbrk
#define RT_STRSCPY  rt_strscpy
#define RT_STRSCAT  rt_strscat
#define RT_STRPAD   rt_strpad
#define RT_BACKEND  "scalar"
#endif
/* libc_expr and rt_expr are the calls. A void call is written (call, 0). */
#define RT_TIME(libc_expr, rt_expr)                                          \
    do {                                                                     \
        uint64_t lc_[SAMPLES], rt_[SAMPLES];                                 \
        int si_;                                                             \
        size_t k_;                                                           \
        uint64_t t0_, t1_;                                                   \
        volatile uintptr_t sink_ = 0;                                        \
        for (k_ = 0; k_ < WARM; k_++) {                                      \
            sink_ += (uintptr_t)(libc_expr);                                 \
            sink_ += (uintptr_t)(rt_expr);                                   \
        }                                                                    \
        for (si_ = 0; si_ < SAMPLES; si_++) {                                \
            t0_ = now_ns();                                                  \
            for (k_ = 0; k_ < (size_t)ITER_STR; k_++)                        \
                sink_ += (uintptr_t)(libc_expr);                             \
            t1_ = now_ns();                                                  \
            lc_[si_] = t1_ - t0_;                                            \
            t0_ = now_ns();                                                  \
            for (k_ = 0; k_ < (size_t)ITER_STR; k_++)                        \
                sink_ += (uintptr_t)(rt_expr);                               \
            t1_ = now_ns();                                                  \
            rt_[si_] = t1_ - t0_;                                            \
        }                                                                    \
        r->libc_ns = median_u64(lc_, SAMPLES);                              \
        r->rt_ns = median_u64(rt_, SAMPLES);                                 \
        (void)sink_;                                                         \
    } while (0)

#define RT_TIME_RT(rt_expr)                                                  \
    do {                                                                     \
        uint64_t rt_[SAMPLES];                                               \
        int si_;                                                             \
        size_t k_;                                                           \
        uint64_t t0_, t1_;                                                   \
        volatile uintptr_t sink_ = 0;                                        \
        r->no_libc = 1;                                                      \
        for (k_ = 0; k_ < WARM; k_++)                                        \
            sink_ += (uintptr_t)(rt_expr);                                   \
        for (si_ = 0; si_ < SAMPLES; si_++) {                                \
            t0_ = now_ns();                                                  \
            for (k_ = 0; k_ < (size_t)ITER_STR; k_++)                        \
                sink_ += (uintptr_t)(rt_expr);                               \
            t1_ = now_ns();                                                  \
            rt_[si_] = t1_ - t0_;                                            \
        }                                                                    \
        r->rt_ns = median_u64(rt_, SAMPLES);                                 \
        (void)sink_;                                                         \
    } while (0)

static size_t ref_strlen_local(const char *s)
{
    size_t n = 0;
    while (s[n] != '\0')
        n++;
    return n;
}

static size_t ref_strscpy(char *dst, const char *src, size_t n)
{
    size_t i = 0;
    size_t len = ref_strlen_local(src);
    if (n == 0)
        return len;
    while (i + 1 < n && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
    return len;
}

static size_t ref_strscat(char *dst, const char *src, size_t n)
{
    size_t used = 0;
    while (used < n && dst[used] != '\0')
        used++;
    if (used >= n)
        return used + ref_strlen_local(src);
    return used + ref_strscpy(dst + used, src, n - used);
}

static void ref_strpad(char *dst, const char *src, size_t width, int fill)
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

static void fill_pat(char *s, size_t n, int ch)
{
    size_t i;
    for (i = 0; i < n; i++)
        s[i] = (char)(ch < 0 ? ('A' + (int)(i % 26)) : ch);
    s[n] = 0;
}

static void bench_bounded_rvv(struct row *r, int kind)
{
    static const size_t lens[] = { 0, 1, 2, 3, 7, 8, 15, 16, 17, 31, 32, 63, 64 };
    static char src[160] __attribute__((aligned(64)));
    static char da[160] __attribute__((aligned(64)));
    static char db[160] __attribute__((aligned(64)));
    size_t li;

    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        size_t n = lens[li];
        size_t cap;
        fill_pat(src, n, -1);
        if (n > 2)
            src[n / 2] = (char)0xFF;
        for (cap = 0; cap <= n + 3 && cap <= 80; cap++) {
            memset(da, 0xA5, sizeof da);
            memset(db, 0xA5, sizeof db);
            if (kind == 0) {
                row_add(r, RT_STRNCPY(db, src, cap) == db &&
                        strncpy(da, src, cap) == da &&
                        memcmp(da, db, cap + 1) == 0);
            } else {
                size_t lim = cap < 40 ? cap : 40;
                row_add(r, RT_STRNLEN(src, lim) == strnlen(src, lim));
            }
        }
    }
    fill_pat(src, 64, -1);
    if (kind == 0)
        RT_TIME(strncpy(da, src, 48), RT_STRNCPY(db, src, 48));
    else
        RT_TIME(strnlen(src, 40), RT_STRNLEN(src, 40));
}

static void bench_copy_rvv(struct row *r)
{
    static const size_t lens[] = { 0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 127 };
    static char src[256] __attribute__((aligned(64)));
    static char da[256] __attribute__((aligned(64)));
    static char db[256] __attribute__((aligned(64)));
    size_t li;

    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        size_t n = lens[li];
        fill_pat(src, n, -1);
        if (n)
            src[n - 1] = (char)0xFF;
        memset(da, 0xA5, sizeof da);
        memset(db, 0xA5, sizeof db);
        row_add(r, strcpy(da, src) == da && RT_STRCPY(db, src) == db &&
                memcmp(da, db, n + 2) == 0);
    }
    fill_pat(src, 128, -1);
    RT_TIME(strcpy(da, src), RT_STRCPY(db, src));
}

static void bench_cat_rvv(struct row *r, int bounded)
{
    static char src[128] __attribute__((aligned(64)));
    static char da[256] __attribute__((aligned(64)));
    static char db[256] __attribute__((aligned(64)));
    static const size_t lens[] = { 0, 1, 3, 8, 16, 31 };
    size_t li;

    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        size_t n = lens[li];
        fill_pat(src, n, -1);
        memset(da, 0xA5, sizeof da);
        memset(db, 0xA5, sizeof db);
        memcpy(da, "pre", 4);
        memcpy(db, "pre", 4);
        if (!bounded) {
            row_add(r, strcat(da, src) == da && RT_STRCAT(db, src) == db &&
                    memcmp(da, db, 4 + n + 2) == 0);
        } else {
            row_add(r, strncat(da, src, 4) == da &&
                    RT_STRNCAT(db, src, 4) == db &&
                    memcmp(da, db, 16) == 0);
            memset(da, 0xA5, sizeof da);
            memset(db, 0xA5, sizeof db);
            memcpy(da, "pre", 4);
            memcpy(db, "pre", 4);
            row_add(r, strncat(da, src, 80) == da &&
                    RT_STRNCAT(db, src, 80) == db &&
                    memcmp(da, db, 4 + n + 2) == 0);
        }
    }
    fill_pat(src, 32, -1);
    if (!bounded)
        RT_TIME((memcpy(da, "head", 5), strcat(da, src)),
                (memcpy(db, "head", 5), RT_STRCAT(db, src)));
    else
        RT_TIME((memcpy(da, "head", 5), strncat(da, src, 16)),
                (memcpy(db, "head", 5), RT_STRNCAT(db, src, 16)));
}

static void bench_strncmp_rvv(struct row *r)
{
    static char a[128] __attribute__((aligned(64)));
    static char b[128] __attribute__((aligned(64)));
    char hi[4], lo[4];
    size_t n;

    row_add(r, RT_STRNCMP("abc", "xyz", 0) == 0);
    row_add(r, RT_STRNCMP("abc", "abd", 2) == strncmp("abc", "abd", 2));
    row_add(r, sign_eq(RT_STRNCMP("abc", "abd", 3), strncmp("abc", "abd", 3)));
    row_add(r, sign_eq(RT_STRNCMP("ab", "abcd", 4), strncmp("ab", "abcd", 4)));
    hi[0] = (char)0xFF;
    hi[1] = 0;
    lo[0] = 1;
    lo[1] = 0;
    row_add(r, sign_eq(RT_STRNCMP(hi, lo, 2), strncmp(hi, lo, 2)));
    row_add(r, sign_eq(RT_STRNCMP(lo, hi, 2), strncmp(lo, hi, 2)));
    for (n = 0; n <= 64; n++) {
        fill_pat(a, 80, -1);
        fill_pat(b, 80, -1);
        if (n < 80)
            b[n] = (char)(b[n] + 1);
        row_add(r, sign_eq(RT_STRNCMP(a, b, n), strncmp(a, b, n)));
    }
    fill_pat(a, 64, -1);
    fill_pat(b, 64, -1);
    b[40] = 'z';
    RT_TIME(strncmp(a, b, 64), RT_STRNCMP(a, b, 64));
}

static void bench_find_rvv(struct row *r, int last, int brk)
{
    static char hay[256] __attribute__((aligned(64)));
    const char *p;
    const char *q;

    fill_pat(hay, 80, -1);
    hay[10] = 'Z';
    hay[40] = 'Z';
    if (last) {
        p = strrchr(hay, 'Z');
        q = RT_STRRCHR(hay, 'Z');
        row_add(r, p == q);
        row_add(r, RT_STRRCHR(hay, 'q') == 0);
        row_add(r, RT_STRRCHR(hay, 0) == strrchr(hay, 0));
        row_add(r, RT_STRRCHR(hay, 256 + 'Z') == strrchr(hay, 256 + 'Z'));
        RT_TIME(strrchr(hay, 'Z'), RT_STRRCHR(hay, 'Z'));
    } else if (!brk) {
        row_add(r, RT_STRSTR(hay, "Z") == strstr(hay, "Z"));
        row_add(r, RT_STRSTR(hay, "") == hay);
        row_add(r, RT_STRSTR(hay, "no-such") == 0);
        row_add(r, RT_STRSTR("ababcabcd", "abc") == strstr("ababcabcd", "abc"));
        row_add(r, RT_STRSTR("", "a") == 0);
        {
            char hi[8];
            memcpy(hi, "a\377b", 4);
            row_add(r, RT_STRSTR(hi, "\377b") == hi + 1);
        }
        RT_TIME(strstr(hay, "Z"), RT_STRSTR(hay, "Z"));
    } else {
        row_add(r, RT_STRPBRK(hay, "Z") == strpbrk(hay, "Z"));
        row_add(r, RT_STRPBRK(hay, "") == 0);
        row_add(r, RT_STRPBRK(hay, "q") == 0);
        row_add(r, RT_STRPBRK("abc", "cba") == strpbrk("abc", "cba"));
        RT_TIME(strpbrk(hay, "Z"), RT_STRPBRK(hay, "Z"));
    }
}

static void bench_nolibc_rvv(struct row *r, int kind)
{
    static char src[64] __attribute__((aligned(64)));
    static char da[96] __attribute__((aligned(64)));
    static char db[96] __attribute__((aligned(64)));
    size_t n;

    fill_pat(src, 10, -1);
    src[3] = (char)0xFF;
    for (n = 0; n <= 16; n++) {
        memset(da, 0xA5, sizeof da);
        memset(db, 0xA5, sizeof db);
        if (kind == 0) {
            row_add(r, ref_strscpy(da, src, n) == RT_STRSCPY(db, src, n) &&
                    memcmp(da, db, 24) == 0);
        } else if (kind == 1) {
            memcpy(da, "pre", 4);
            memcpy(db, "pre", 4);
            row_add(r, ref_strscat(da, src, n) == RT_STRSCAT(db, src, n) &&
                    memcmp(da, db, 24) == 0);
        } else {
            ref_strpad(da, src, n, 0x141);
            RT_STRPAD(db, src, n, 0x141);
            row_add(r, memcmp(da, db, n + 1) == 0);
        }
    }
    fill_pat(src, 32, -1);
    if (kind == 0)
        RT_TIME_RT(RT_STRSCPY(db, src, 24));
    else if (kind == 1)
        RT_TIME_RT((memcpy(db, "pre", 4), RT_STRSCAT(db, src, 24)));
    else
        RT_TIME_RT((RT_STRPAD(db, src, 24, ' '), 0));
}

static void run_strings_riscv(void)
{
    struct row *r;

    r = row_begin("strlen", RT_BACKEND, GRP_STRING);
    if (r) bench_strlen_fn(r, RT_STRLEN);
    r = row_begin("strnlen", RT_BACKEND, GRP_STRING);
    if (r) bench_bounded_rvv(r, 1);
    r = row_begin("strcpy", RT_BACKEND, GRP_STRING);
    if (r) bench_copy_rvv(r);
    r = row_begin("strncpy", RT_BACKEND, GRP_STRING);
    if (r) bench_bounded_rvv(r, 0);
    r = row_begin("strcat", RT_BACKEND, GRP_STRING);
    if (r) bench_cat_rvv(r, 0);
    r = row_begin("strncat", RT_BACKEND, GRP_STRING);
    if (r) bench_cat_rvv(r, 1);
    r = row_begin("strcmp", RT_BACKEND, GRP_STRING);
    if (r) bench_strcmp_fn(r, RT_STRCMP);
    r = row_begin("strncmp", RT_BACKEND, GRP_STRING);
    if (r) bench_strncmp_rvv(r);
    r = row_begin("strchr", RT_BACKEND, GRP_STRING);
    if (r) bench_strchr_fn(r, RT_STRCHR);
    r = row_begin("strrchr", RT_BACKEND, GRP_STRING);
    if (r) bench_find_rvv(r, 1, 0);
    r = row_begin("strstr", RT_BACKEND, GRP_STRING);
    if (r) bench_find_rvv(r, 0, 0);
    r = row_begin("strpbrk", RT_BACKEND, GRP_STRING);
    if (r) bench_find_rvv(r, 0, 1);
    r = row_begin("strscpy", RT_BACKEND, GRP_STRING);
    if (r) bench_nolibc_rvv(r, 0);
    r = row_begin("strscat", RT_BACKEND, GRP_STRING);
    if (r) bench_nolibc_rvv(r, 1);
    r = row_begin("strpad", RT_BACKEND, GRP_STRING);
    if (r) bench_nolibc_rvv(r, 2);
}

#undef RT_TIME
#undef RT_TIME_RT
#undef RT_STRLEN
#undef RT_STRNLEN
#undef RT_STRCPY
#undef RT_STRNCPY
#undef RT_STRCAT
#undef RT_STRNCAT
#undef RT_STRCMP
#undef RT_STRNCMP
#undef RT_STRCHR
#undef RT_STRRCHR
#undef RT_STRSTR
#undef RT_STRPBRK
#undef RT_STRSCPY
#undef RT_STRSCAT
#undef RT_STRPAD
#undef RT_BACKEND
#endif

#if (defined(__aarch64__) || defined(__arm64__)) && defined(RT_RUN_NEON)
static void run_strings_neon(void)
{
    struct row *r;
    r = row_begin("strlen", "neon", GRP_STRING);
    if (r) bench_strlen_fn(r, rt_strlen_neon);
    r = row_begin("strcmp", "neon", GRP_STRING);
    if (r) bench_strcmp_fn(r, rt_strcmp_neon);
    r = row_begin("strchr", "neon", GRP_STRING);
    if (r) bench_strchr_fn(r, rt_strchr_neon);
}
#endif

/* ===================== NUMERIC / SORT / FORMAT / ALLOC ===================== */

static int icmp(const void *a, const void *b)
{
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

static long end_off(const char *s, const char *e)
{
    const char *p;
    long off = 0;
    if (!e)
        return -1;
    for (p = s; ; p++, off++) {
        if (p == e)
            return off;
        if (*p == '\0')
            return -1;
    }
}

/* Value and end pointer, including a rejected 0x prefix and overflow. */
static int ul_ok(const char *s, int base)
{
    char *e1 = 0, *e2 = 0;
    unsigned long a = rt_strtoul(s, &e1, base);
    unsigned long b = strtoul(s, &e2, base);
    long o1 = end_off(s, e1);
    long o2 = end_off(s, e2);
    if (a == b && o1 >= 0 && o1 == o2)
        return 1;
    printf("strtoul \"%s\" base %d: rt %lu end %ld, libc %lu end %ld\n",
           s, base, a, o1, b, o2);
    return 0;
}

static int ull_ok(const char *s, int base)
{
    char *e1 = 0, *e2 = 0;
    unsigned long long a = rt_strtoull(s, &e1, base);
    unsigned long long b = strtoull(s, &e2, base);
    long o1 = end_off(s, e1);
    long o2 = end_off(s, e2);
    if (a == b && o1 >= 0 && o1 == o2)
        return 1;
    printf("strtoull \"%s\" base %d: rt %llu end %ld, libc %llu end %ld\n",
           s, base, a, o1, b, o2);
    return 0;
}

static int sorted_ints(const int *v, size_t n)
{
    size_t i;
    for (i = 1; i < n; i++) {
        if (v[i - 1] > v[i])
            return 0;
    }
    return 1;
}

/* Sorted output must be the same multiset. Tie order is not libc's order. */
static int same_multiset(const int *orig, const int *sorted, size_t n)
{
    size_t i, j;
    unsigned char used[1024];
    if (n > sizeof used)
        return 0;
    for (i = 0; i < n; i++)
        used[i] = 0;
    for (i = 0; i < n; i++) {
        int found = 0;
        for (j = 0; j < n; j++) {
            if (!used[j] && orig[j] == sorted[i]) {
                used[j] = 1;
                found = 1;
                break;
            }
        }
        if (!found)
            return 0;
    }
    return 1;
}

static int f32_is(float x, const char *expect)
{
    char buf[64];
    size_t i, el;
    int n;
    memset(buf, 0xA5, sizeof buf);
    n = rt_fmt_f32(buf, sizeof buf, x);
    el = strlen(expect);
    if (n < 0 || (size_t)n != el || strcmp(buf, expect) != 0)
        return 0;
    for (i = el + 1; i < sizeof buf; i++) {
        if ((unsigned char)buf[i] != 0xA5)
            return 0;
    }
    return 1;
}

__attribute__((unused))
static void run_numeric(void)
{
    struct row *r;
    size_t i;
    uint64_t t0, t1;
    size_t k;
    volatile long sink = 0;

    r = row_begin("atoi", "scalar", GRP_NUMERIC);
    {
        static const char *s[] = {
            "0", "42", "-7", "  99", "2147483647", "-2147483648",
            "", "+42", "  -12", "42abc", "+", "  +0"
        };
        for (i = 0; i < sizeof s / sizeof s[0]; i++)
            row_add(r, rt_atoi(s[i]) == atoi(s[i]));
        static char digits[] __attribute__((aligned(64))) = "123456";
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += atoi(digits);
        t1 = now_ns();
        if (r) r->libc_ns = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += rt_atoi(digits);
        t1 = now_ns();
        if (r) r->rt_ns = t1 - t0;
    }

    r = row_begin("strtoul", "scalar", GRP_NUMERIC);
    {
        row_add(r, ul_ok("0", 10));
        row_add(r, ul_ok("42", 10));
        row_add(r, ul_ok("  42", 10));
        row_add(r, ul_ok("42abc", 10));
        row_add(r, ul_ok("", 10));
        row_add(r, ul_ok("-1", 10));
        row_add(r, ul_ok("0x10", 0));
        row_add(r, ul_ok("010", 0));
        row_add(r, ul_ok("10", 0));
        row_add(r, ul_ok("0xff", 16));
        row_add(r, ul_ok("077", 8));
        row_add(r, ul_ok("0x", 16));
        row_add(r, ul_ok("0xG", 16));
        row_add(r, ul_ok("18446744073709551616", 10));
        static char digits[] __attribute__((aligned(64))) = "12345678";
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)strtoul(digits, 0, 10);
        t1 = now_ns();
        if (r) r->libc_ns = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)rt_strtoul(digits, 0, 10);
        t1 = now_ns();
        if (r) r->rt_ns = t1 - t0;
    }

    r = row_begin("strtoull", "scalar", GRP_NUMERIC);
    {
        row_add(r, ull_ok("1234567890123", 10));
        row_add(r, ull_ok("0xDeadBeef", 0));
        row_add(r, ull_ok("0x", 16));
        row_add(r, ull_ok("-1", 10));
        row_add(r, ull_ok("18446744073709551616", 10));
        row_add(r, ull_ok("18446744073709551615", 10));
        static char digits[] __attribute__((aligned(64))) = "0x123456789";
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)strtoull(digits, 0, 0);
        t1 = now_ns();
        if (r) r->libc_ns = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)rt_strtoull(digits, 0, 0);
        t1 = now_ns();
        if (r) r->rt_ns = t1 - t0;
    }
    (void)sink;
}

__attribute__((unused))
static void run_sort(void)
{
    struct row *r;
    int a[1024] __attribute__((aligned(64))) = {0};
    int b[1024] __attribute__((aligned(64))) = {0};
    int c[1024] __attribute__((aligned(64))) = {0};
    size_t n, k;
    uint64_t t0, t1;
    int si;
    uint64_t lc[SAMPLES], rt_t[SAMPLES];
    enum { N = 512, LOOPS = 16 };

    /* rt_qsort_simple (Ciura shell) stays in the library. The oracle times rt_qsort. */
    r = row_begin("qsort", "scalar", GRP_SORT);
    for (n = 0; n <= 128; n++) {
        for (k = 0; k < n; k++)
            a[k] = c[k] = (int)(rnd() % 1000u) - 500;
        rt_qsort(a, n, sizeof(int), icmp);
        row_add(r, sorted_ints(a, n) && same_multiset(c, a, n));
    }
    for (k = 0; k < (size_t)N; k++)
        c[k] = b[k] = (int)k;
    rt_qsort(b, (size_t)N, sizeof(int), icmp);
    row_add(r, sorted_ints(b, (size_t)N) && same_multiset(c, b, (size_t)N));
    for (k = 0; k < (size_t)N; k++)
        c[k] = b[k] = (int)((size_t)N - k);
    rt_qsort(b, (size_t)N, sizeof(int), icmp);
    row_add(r, sorted_ints(b, (size_t)N) && same_multiset(c, b, (size_t)N));
    for (k = 0; k < (size_t)N; k++)
        c[k] = b[k] = 7;
    rt_qsort(b, (size_t)N, sizeof(int), icmp);
    row_add(r, sorted_ints(b, (size_t)N) && same_multiset(c, b, (size_t)N));
    b[0] = 3;
    b[1] = 1;
    rt_qsort(b, 2, 0, icmp);
    row_add(r, b[0] == 3 && b[1] == 1);
    rt_qsort(b, 1, sizeof(int), icmp);
    row_add(r, b[0] == 3);

    for (k = 0; k < (size_t)N; k++)
        a[k] = b[k] = (int)(rnd() % 100000u);
    for (k = 0; k < WARM; k++) {
        memcpy(a, b, sizeof(int) * (size_t)N);
        qsort(a, (size_t)N, sizeof(int), icmp);
        memcpy(a, b, sizeof(int) * (size_t)N);
        rt_qsort(a, (size_t)N, sizeof(int), icmp);
    }
    for (si = 0; si < SAMPLES; si++) {
        t0 = now_ns();
        for (k = 0; k < (size_t)LOOPS; k++) {
            memcpy(a, b, sizeof(int) * (size_t)N);
            qsort(a, (size_t)N, sizeof(int), icmp);
        }
        t1 = now_ns();
        lc[si] = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < (size_t)LOOPS; k++) {
            memcpy(a, b, sizeof(int) * (size_t)N);
            rt_qsort(a, (size_t)N, sizeof(int), icmp);
        }
        t1 = now_ns();
        rt_t[si] = t1 - t0;
    }
    if (r) {
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
}

__attribute__((unused))
static void run_format(void)
{
    struct row *r;
    char a[128] __attribute__((aligned(64)));
    char b[128] __attribute__((aligned(64)));
    static char item[] __attribute__((aligned(64))) = "item";
    int ra, rb;
    size_t k;
    uint64_t t0, t1;

    r = row_begin("snprintf", "scalar", GRP_FORMAT);
    ra = rt_snprintf(a, sizeof a, "%d %s %x", 42, "hi", 0xabc);
    rb = snprintf(b, sizeof b, "%d %s %x", 42, "hi", 0xabc);
    row_add(r, ra == rb && strcmp(a, b) == 0);
    ra = rt_snprintf(a, sizeof a, "%05d %-5s", 7, "ab");
    rb = snprintf(b, sizeof b, "%05d %-5s", 7, "ab");
    row_add(r, ra == rb && strcmp(a, b) == 0);
    ra = rt_snprintf(a, sizeof a, "%% %u %d", 0u, -42);
    rb = snprintf(b, sizeof b, "%% %u %d", 0u, -42);
    row_add(r, ra == rb && strcmp(a, b) == 0);
    ra = rt_snprintf(a, sizeof a, "%.2s", "abcd");
    rb = snprintf(b, sizeof b, "%.2s", "abcd");
    row_add(r, ra == rb && strcmp(a, b) == 0);
    memset(a, 0xA5, sizeof a);
    ra = rt_snprintf(a, 0, "hi");
    {
        int same = 1;
        size_t bi;
        for (bi = 0; bi < sizeof a; bi++) {
            if ((unsigned char)a[bi] != 0xA5)
                same = 0;
        }
        row_add(r, ra == 2 && same);
    }
    memset(a, 0xA5, sizeof a);
    ra = rt_snprintf(a, 1, "hi");
    row_add(r, ra == 2 && a[0] == '\0' && (unsigned char)a[1] == 0xA5);
    memset(a, 0xA5, sizeof a);
    ra = rt_snprintf(a, 5, "abcdefgh");
    row_add(r, ra == 8 && strcmp(a, "abcd") == 0 && (unsigned char)a[5] == 0xA5);
    memset(a, 0xA5, sizeof a);
    ra = rt_snprintf(a, sizeof a, "%s", (const char *)0);
    row_add(r, ra == 6 && strcmp(a, "(null)") == 0);
    memset(a, 0xA5, sizeof a);
    ra = rt_snprintf(a, sizeof a, NULL);
    row_add(r, ra == 0 && a[0] == '\0' && (unsigned char)a[1] == 0xA5);

    t0 = now_ns();
    for (k = 0; k < ITER_FMT; k++)
        snprintf(b, sizeof b, "%d-%s-%x", (int)k, item, (unsigned)k);
    t1 = now_ns();
    if (r) r->libc_ns = t1 - t0;

    t0 = now_ns();
    for (k = 0; k < ITER_FMT; k++)
        rt_snprintf(a, sizeof a, "%d-%s-%x", (int)k, item, (unsigned)k);
    t1 = now_ns();
    if (r) r->rt_ns = t1 - t0;

    r = row_begin("fmt_f32", "scalar", GRP_FORMAT);
    {
        union { uint32_t u; float f; } bits;
        char small[16];
        int n;
        size_t bi;
        int tail = 1;
        row_add(r, f32_is(0.0f, "0.000000"));
        row_add(r, f32_is(1.0f, "1.000000"));
        row_add(r, f32_is(-2.5f, "-2.500000"));
        row_add(r, f32_is(0.5f, "0.500000"));
        row_add(r, f32_is(10.0f, "10.000000"));
        bits.u = 0x80000000u;
        row_add(r, f32_is(bits.f, "-0.000000"));
        bits.u = 0x7f800000u;
        row_add(r, f32_is(bits.f, "inf"));
        bits.u = 0xff800000u;
        row_add(r, f32_is(bits.f, "-inf"));
        bits.u = 0x7fc00000u;
        row_add(r, f32_is(bits.f, "nan"));
        memset(small, 0xA5, sizeof small);
        n = rt_fmt_f32(small, 4, 1.0f);
        for (bi = 4; bi < sizeof small; bi++) {
            if ((unsigned char)small[bi] != 0xA5)
                tail = 0;
        }
        row_add(r, n == 8 && memcmp(small, "1.0", 4) == 0 && tail);
        t0 = now_ns();
        for (k = 0; k < ITER_FMT; k++)
            rt_fmt_f32(a, sizeof a, 3.141592f);
        t1 = now_ns();
        if (r) {
            r->rt_ns = t1 - t0;
            r->libc_ns = t1 - t0; /* no direct libc equivalent */
        }
    }
}

__attribute__((unused))
static void run_alloc(void)
{
    struct row *r = row_begin("alloc", "scalar", GRP_ALLOC);
    static unsigned char pool[8192] __attribute__((aligned(64)));
    void *p1, *p2, *p3;
    size_t k;
    uint64_t t0, t1;

    rt_alloc_init(pool, sizeof pool);
    row_add(r, rt_malloc(0) == 0);
    rt_free(0);
    row_add(r, rt_calloc((size_t)-1, (size_t)-1) == 0);
    row_add(r, rt_calloc(4, 0) == 0 && rt_calloc(0, 4) == 0);
    p2 = rt_calloc(10, 4);
    row_add(r, p2 != 0);
    if (p2) {
        int z = 1;
        size_t i;
        for (i = 0; i < 40; i++)
            if (((unsigned char *)p2)[i]) z = 0;
        row_add(r, z);
    }
    p1 = rt_malloc(100);
    row_add(r, p1 && p1 != p2);
    if (p1) {
        unsigned char expect[100];
        size_t i;
        for (i = 0; i < 100; i++) {
            ((unsigned char *)p1)[i] = 0x5A;
            expect[i] = 0x5A;
        }
        if (p2) {
            int apart = 1;
            for (i = 0; i < 40; i++) {
                if (((unsigned char *)p2)[i])
                    apart = 0;
            }
            row_add(r, apart);
        }
        p3 = rt_realloc(p1, 200);
        if (!p3) {
            row_add(r, 0);
            rt_free(p1);
        } else {
            row_add(r, memcmp(p3, expect, 100) == 0);
            rt_free(p3);
        }
    }
    rt_free(p2);
    p1 = rt_realloc(0, 24);
    row_add(r, p1 != 0);
    rt_free(p1);
    rt_alloc_init(pool, sizeof pool);
    {
        size_t nblk = 0;
        for (;;) {
            void *p = rt_malloc(256);
            if (!p)
                break;
            nblk++;
            if (nblk > 1000)
                break;
        }
        row_add(r, nblk > 0 && nblk < 1000 && rt_malloc(256) == 0);
    }
    rt_alloc_init(pool, sizeof pool);

    t0 = now_ns();
    for (k = 0; k < 256; k++) {
        void *p = malloc(64);
        free(p);
    }
    t1 = now_ns();
    if (r) r->libc_ns = t1 - t0;

    t0 = now_ns();
    for (k = 0; k < 256; k++) {
        void *p = rt_malloc(64);
        rt_free(p);
    }
    t1 = now_ns();
    if (r) r->rt_ns = t1 - t0;
}

#if defined(__i386__) && !defined(__x86_64__)
static int cpuid_edx_bit(unsigned bit)
{
    unsigned eax, ebx, ecx, edx, max;
    __asm__ volatile("cpuid" : "=a"(max), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(0));
    if (max < 1)
        return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1));
    return (edx & (1u << bit)) != 0;
}
static int have_mmx(void) { return cpuid_edx_bit(23); }
static int have_sse(void) { return cpuid_edx_bit(25); }
static int have_sse2(void) { return cpuid_edx_bit(26); }
#elif defined(__x86_64__)
static unsigned long long xcr0(void)
{
    unsigned eax, edx;
    __asm__ volatile("xgetbv" : "=a"(eax), "=d"(edx) : "c"(0));
    return ((unsigned long long)edx << 32) | eax;
}
static int have_avx(void)
{
    unsigned eax, ebx, ecx, edx, max;
    __asm__ volatile("cpuid" : "=a"(max), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(0));
    if (max < 1) return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1));
    if ((ecx & (1u << 27)) == 0 || (ecx & (1u << 28)) == 0) return 0;
    return (xcr0() & 0x6ull) == 0x6ull;
}
static int have_avx2(void)
{
    unsigned eax, ebx, ecx, edx;
    if (!have_avx()) return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(7), "c"(0));
    return (ebx & (1u << 5)) != 0;
}
static int have_avx512(void)
{
    unsigned eax, ebx, ecx, edx;
    if (!have_avx2()) return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(7), "c"(0));
    if ((ebx & (1u << 16)) == 0 || (ebx & (1u << 30)) == 0) return 0;
    return (xcr0() & 0xE6ull) == 0xE6ull;
}
#endif

#if defined(__APPLE__) && defined(RT_RUN_SCALAR)
/* bl / blr / br / adrp. The scalar leaf has none of these. */
static int insn_leaves(uint32_t w)
{
    if ((w & 0xfc000000u) == 0x94000000u) return 1;
    if ((w & 0xfffffc1fu) == 0xd63f0000u) return 1;
    if ((w & 0xfffffc1fu) == 0xd61f0000u) return 1;
    if ((w & 0x9f000000u) == 0x90000000u) return 1;
    return 0;
}

/* On-disk arm64 __platform_memset, plus the __platform_bzero it branches
   into for a large zero. The live dyld memset is the NEON body. */
static set_fn map_apple_scalar_memset(void)
{
    int fd;
    struct stat st;
    unsigned char *file;
    uint32_t mag;
    uint32_t slice = 0, slice_sz = 0;
    const unsigned char *base;
    const struct mach_header_64 *mh;
    uint32_t coff, c;
    uint64_t text_vm = 0, text_file = 0;
    const struct symtab_command *sy = 0;
    const struct nlist_64 *nl;
    const char *strtab;
    uint64_t bzero_vm = 0, memset_vm = 0, limit_vm = 0;
    const uint32_t *ins;
    size_t nins, keep, pagesz, mapn, i;
    unsigned char *exec;

    fd = open("/usr/lib/system/libsystem_platform.dylib", O_RDONLY);
    if (fd < 0)
        return 0;
    if (fstat(fd, &st) != 0 || st.st_size < 64) {
        close(fd);
        return 0;
    }
    file = mmap(0, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (file == MAP_FAILED)
        return 0;
    memcpy(&mag, file, 4);
    if (mag == FAT_CIGAM) {
        uint32_t nfat = OSSwapBigToHostInt32(*(uint32_t *)(file + 4));
        for (i = 0; i < nfat; i++) {
            const unsigned char *a = file + 8 + i * 20;
            uint32_t cputype = OSSwapBigToHostInt32(*(uint32_t *)a);
            uint32_t subtype = OSSwapBigToHostInt32(*(uint32_t *)(a + 4));
            uint32_t off = OSSwapBigToHostInt32(*(uint32_t *)(a + 8));
            uint32_t sz = OSSwapBigToHostInt32(*(uint32_t *)(a + 12));
            if (cputype == CPU_TYPE_ARM64 &&
                (subtype & 0xffu) == CPU_SUBTYPE_ARM64_ALL) {
                slice = off;
                slice_sz = sz;
                break;
            }
        }
    } else if (mag == MH_MAGIC_64) {
        slice = 0;
        slice_sz = (uint32_t)st.st_size;
    }
    if (slice_sz < sizeof(struct mach_header_64) ||
        (off_t)slice + (off_t)slice_sz > st.st_size) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    base = file + slice;
    mh = (const struct mach_header_64 *)base;
    if (mh->magic != MH_MAGIC_64) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    coff = 0;
    for (c = 0; c < mh->ncmds; c++) {
        const struct load_command *lc =
            (const struct load_command *)(base + sizeof(*mh) + coff);
        if (lc->cmdsize < 8 || coff + lc->cmdsize > mh->sizeofcmds)
            break;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sg =
                (const struct segment_command_64 *)lc;
            if (strcmp(sg->segname, "__TEXT") == 0) {
                text_vm = sg->vmaddr;
                text_file = sg->fileoff;
            }
        } else if (lc->cmd == LC_SYMTAB) {
            sy = (const struct symtab_command *)lc;
        }
        coff += lc->cmdsize;
    }
    if (!sy || sy->nsyms == 0) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    nl = (const struct nlist_64 *)(base + sy->symoff);
    strtab = (const char *)(base + sy->stroff);
    for (i = 0; i < sy->nsyms; i++) {
        const char *name = strtab + nl[i].n_un.n_strx;
        if (strcmp(name, "__platform_bzero") == 0)
            bzero_vm = nl[i].n_value;
        else if (strcmp(name, "__platform_memset") == 0)
            memset_vm = nl[i].n_value;
        else if (strcmp(name, "__platform_memmove") == 0)
            limit_vm = nl[i].n_value;
    }
    if (memset_vm < bzero_vm || limit_vm <= memset_vm || bzero_vm == 0) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    ins = (const uint32_t *)(base + text_file + (bzero_vm - text_vm));
    nins = (size_t)((limit_vm - bzero_vm) / 4u);
    keep = nins;
    for (i = 0; i < nins; i++) {
        if (insn_leaves(ins[i])) {
            keep = i;
            break;
        }
    }
    if (keep * 4u < (size_t)(memset_vm - bzero_vm) + 16u) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    pagesz = (size_t)sysconf(_SC_PAGESIZE);
    mapn = (keep * 4u + pagesz - 1u) & ~(pagesz - 1u);
    exec = mmap(0, mapn, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (exec == MAP_FAILED) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    memcpy(exec, ins, keep * 4u);
    if (mprotect(exec, mapn, PROT_READ | PROT_EXEC) != 0) {
        munmap(exec, mapn);
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    sys_icache_invalidate(exec, keep * 4u);
    munmap(file, (size_t)st.st_size);
    return (set_fn)(exec + (memset_vm - bzero_vm));
}

/* adr, and LDR (literal) of any width. A copied leaf cannot use them. */
static int insn_pcrel_load(uint32_t w)
{
    uint32_t top;
    if ((w & 0x9f000000u) == 0x10000000u)
        return 1;
    top = w >> 24;
    return top == 0x18u || top == 0x58u || top == 0x98u ||
           top == 0x1cu || top == 0x5cu || top == 0x9cu || top == 0xd8u;
}

/* b / b.cond / cbz / cbnz / tbz / tbnz. Returns the target VM address. */
static int insn_branch_target(uint32_t w, uint64_t pc, uint64_t *tgt)
{
    int64_t imm;
    if ((w & 0xfc000000u) == 0x14000000u) {
        imm = (int64_t)((int32_t)(w << 6) >> 6);
        *tgt = (uint64_t)((int64_t)pc + imm * 4);
        return 1;
    }
    if ((w & 0xff000010u) == 0x54000000u || (w & 0x7e000000u) == 0x34000000u) {
        imm = (int64_t)((w >> 5) & 0x7ffffu);
        if (imm & 0x40000)
            imm -= 0x80000;
        *tgt = (uint64_t)((int64_t)pc + imm * 4);
        return 1;
    }
    if ((w & 0x7e000000u) == 0x36000000u) {
        imm = (int64_t)((w >> 5) & 0x3fffu);
        if (imm & 0x2000)
            imm -= 0x4000;
        *tgt = (uint64_t)((int64_t)pc + imm * 4);
        return 1;
    }
    return 0;
}

/* On-disk arm64 __platform_memmove through the next symbol. Integer
   ldp/stp, no call and no PC-relative load. Live memcpy and memmove are
   one NEON body; the scalar table times this leaf for both. */
static copy_fn map_apple_scalar_memmove(void)
{
    int fd;
    struct stat st;
    unsigned char *file;
    uint32_t mag;
    uint32_t slice = 0, slice_sz = 0;
    const unsigned char *base;
    const struct mach_header_64 *mh;
    uint32_t coff, c;
    uint64_t text_vm = 0, text_file = 0, text_end = 0;
    const struct symtab_command *sy = 0;
    const struct nlist_64 *nl;
    const char *strtab;
    uint64_t mv_vm = 0, end_vm = 0;
    const uint32_t *ins;
    size_t nins, pagesz, mapn, i;
    unsigned char *exec;

    fd = open("/usr/lib/system/libsystem_platform.dylib", O_RDONLY);
    if (fd < 0)
        return 0;
    if (fstat(fd, &st) != 0 || st.st_size < 64) {
        close(fd);
        return 0;
    }
    file = mmap(0, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (file == MAP_FAILED)
        return 0;
    memcpy(&mag, file, 4);
    if (mag == FAT_CIGAM) {
        uint32_t nfat = OSSwapBigToHostInt32(*(uint32_t *)(file + 4));
        for (i = 0; i < nfat; i++) {
            const unsigned char *a = file + 8 + i * 20;
            uint32_t cputype = OSSwapBigToHostInt32(*(uint32_t *)a);
            uint32_t subtype = OSSwapBigToHostInt32(*(uint32_t *)(a + 4));
            uint32_t off = OSSwapBigToHostInt32(*(uint32_t *)(a + 8));
            uint32_t sz = OSSwapBigToHostInt32(*(uint32_t *)(a + 12));
            if (cputype == CPU_TYPE_ARM64 &&
                (subtype & 0xffu) == CPU_SUBTYPE_ARM64_ALL) {
                slice = off;
                slice_sz = sz;
                break;
            }
        }
    } else if (mag == MH_MAGIC_64) {
        slice = 0;
        slice_sz = (uint32_t)st.st_size;
    }
    if (slice_sz < sizeof(struct mach_header_64) ||
        (off_t)slice + (off_t)slice_sz > st.st_size) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    base = file + slice;
    mh = (const struct mach_header_64 *)base;
    if (mh->magic != MH_MAGIC_64) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    coff = 0;
    for (c = 0; c < mh->ncmds; c++) {
        const struct load_command *lc =
            (const struct load_command *)(base + sizeof(*mh) + coff);
        if (lc->cmdsize < 8 || coff + lc->cmdsize > mh->sizeofcmds)
            break;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sg =
                (const struct segment_command_64 *)lc;
            if (strcmp(sg->segname, "__TEXT") == 0) {
                text_vm = sg->vmaddr;
                text_file = sg->fileoff;
                text_end = sg->vmaddr + sg->vmsize;
            }
        } else if (lc->cmd == LC_SYMTAB) {
            sy = (const struct symtab_command *)lc;
        }
        coff += lc->cmdsize;
    }
    if (!sy || sy->nsyms == 0 || text_end <= text_vm) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    nl = (const struct nlist_64 *)(base + sy->symoff);
    strtab = (const char *)(base + sy->stroff);
    for (i = 0; i < sy->nsyms; i++) {
        const char *name = strtab + nl[i].n_un.n_strx;
        if (strcmp(name, "__platform_memmove") == 0)
            mv_vm = nl[i].n_value;
    }
    /* The next section symbol is the end of the leaf. */
    end_vm = text_end;
    if (mv_vm != 0) {
        for (i = 0; i < sy->nsyms; i++) {
            uint64_t val = nl[i].n_value;
            if ((nl[i].n_type & N_TYPE) == N_SECT && val > mv_vm && val < end_vm)
                end_vm = val;
        }
    }
    if (mv_vm == 0 || end_vm <= mv_vm || (end_vm - mv_vm) > 4096u ||
        ((end_vm - mv_vm) & 3u) != 0) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    ins = (const uint32_t *)(base + text_file + (mv_vm - text_vm));
    nins = (size_t)((end_vm - mv_vm) / 4u);
    for (i = 0; i < nins; i++) {
        uint64_t tgt = 0;
        if (insn_leaves(ins[i]) || insn_pcrel_load(ins[i])) {
            munmap(file, (size_t)st.st_size);
            return 0;
        }
        if (insn_branch_target(ins[i], mv_vm + i * 4u, &tgt) &&
            (tgt < mv_vm || tgt >= end_vm)) {
            munmap(file, (size_t)st.st_size);
            return 0;
        }
    }
    pagesz = (size_t)sysconf(_SC_PAGESIZE);
    mapn = (nins * 4u + pagesz - 1u) & ~(pagesz - 1u);
    exec = mmap(0, mapn, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (exec == MAP_FAILED) {
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    memcpy(exec, ins, nins * 4u);
    if (mprotect(exec, mapn, PROT_READ | PROT_EXEC) != 0) {
        munmap(exec, mapn);
        munmap(file, (size_t)st.st_size);
        return 0;
    }
    sys_icache_invalidate(exec, nins * 4u);
    munmap(file, (size_t)st.st_size);
    return (copy_fn)exec;
}

/* The 4096-byte oracle row never reaches the dc zva branch (n >= 32 KiB
   and a zero fill). This gate does. */
static int apple_scalar_blob_ok(set_fn fn)
{
    static unsigned char raw[65536 + 256];
    unsigned char *base = (unsigned char *)(((uintptr_t)raw + 63u) & ~(uintptr_t)63u);
    size_t lens[] = { 0, 1, 7, 8, 15, 16, 63, 64, 65, 127, 4096, 32768, 65536 };
    size_t aligns[] = { 0, 1, 63 };
    int fills[] = { 0, 0xA5, 255, -1 };
    size_t li, ai;
    int fi;
    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        for (ai = 0; ai < sizeof aligns / sizeof aligns[0]; ai++) {
            for (fi = 0; fi < (int)(sizeof fills / sizeof fills[0]); fi++) {
                size_t off = aligns[ai], n = lens[li], i;
                unsigned char *d = base + off;
                unsigned char uc = (unsigned char)fills[fi];
                if (d + n + 32 > raw + sizeof raw)
                    continue;
                memset(raw, 0x3C, sizeof raw);
                if (fn(d, fills[fi], n) != d)
                    return 0;
                for (i = 0; i < (size_t)(d - raw); i++)
                    if (raw[i] != 0x3C) return 0;
                for (i = 0; i < n; i++)
                    if (d[i] != uc) return 0;
                for (i = 0; i < 32; i++)
                    if (d[n + i] != 0x3C) return 0;
            }
        }
    }
    return 1;
}

/* Mapped memmove must match live memmove, including the timed shapes:
   a 4096-byte non-overlapping copy and memmove(p+16, p, 2048). */
static int apple_scalar_copy_ok(copy_fn fn)
{
    enum { CAP = 65536 + 256 };
    static unsigned char raw_s[CAP], raw_e[CAP], raw_g[CAP];
    unsigned char *src = (unsigned char *)(((uintptr_t)raw_s + 63u) & ~(uintptr_t)63u);
    unsigned char *exp = (unsigned char *)(((uintptr_t)raw_e + 63u) & ~(uintptr_t)63u);
    unsigned char *got = (unsigned char *)(((uintptr_t)raw_g + 63u) & ~(uintptr_t)63u);
    size_t room = (size_t)((raw_s + CAP) - src);
    size_t lens[] = {
        0, 1, 7, 8, 15, 16, 31, 63, 64, 65, 127, 128, 255, 2048, 4096, 65536
    };
    size_t aligns[] = { 0, 1, 7, 15, 63 };
    size_t offs[] = { 0, 1, 2, 3, 7, 8, 15, 16, 31, 64 };
    size_t li, ai, oi, i;

    if ((size_t)((raw_e + CAP) - exp) < room)
        room = (size_t)((raw_e + CAP) - exp);
    if ((size_t)((raw_g + CAP) - got) < room)
        room = (size_t)((raw_g + CAP) - got);

    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        for (ai = 0; ai < sizeof aligns / sizeof aligns[0]; ai++) {
            size_t n = lens[li], off = aligns[ai];
            void *ret;
            if (off + n + 32 > room)
                continue;
            memset(src, 0x3C, room);
            memset(exp, 0x5A, room);
            memset(got, 0x5A, room);
            for (i = 0; i < n; i++)
                src[off + i] = (unsigned char)(0x11 + (unsigned)(i * 17u));
            memmove(exp + off, src + off, n);
            ret = fn(got + off, src + off, n);
            if (ret != got + off || memcmp(got, exp, room) != 0)
                return 0;
        }
    }
    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        for (oi = 0; oi < sizeof offs / sizeof offs[0]; oi++) {
            size_t n = lens[li], off = offs[oi];
            int above;
            if (n + off + 32 > room)
                continue;
            for (above = 0; above < 2; above++) {
                void *ret;
                unsigned char *ds, *dd;
                memset(src, 0x3C, room);
                for (i = 0; i < n + off; i++)
                    src[i] = (unsigned char)(0x40 + (unsigned)((i * 3u) & 0xFFu));
                memcpy(exp, src, room);
                if (above) {
                    dd = src + off;
                    ds = src;
                } else {
                    dd = src;
                    ds = src + off;
                }
                memmove(exp + (dd - src), exp + (ds - src), n);
                ret = fn(dd, ds, n);
                if (ret != dd || memcmp(src, exp, room) != 0)
                    return 0;
            }
        }
    }
    return 1;
}

#endif

#if defined(__APPLE__) && defined(RT_RUN_SME)
/* x1 is pointer-sized. memset passes the fill in the low byte. */
extern void *rt_sme_call(void *a, uintptr_t b, size_t n, void *fn);
static void *(*g_apple_sme_memset)(void *, int, size_t);
static void *(*g_apple_sme_memcpy)(void *, const void *, size_t);
static void *(*g_apple_sme_memmove)(void *, const void *, size_t);

static void *apple_sme_memset(void *dst, int c, size_t n)
{
    return rt_sme_call(dst, (uintptr_t)(unsigned)c, n, (void *)g_apple_sme_memset);
}

static void *apple_sme_memcpy(void *dst, const void *src, size_t n)
{
    return rt_sme_call(dst, (uintptr_t)src, n, (void *)g_apple_sme_memcpy);
}

static void *apple_sme_memmove(void *dst, const void *src, size_t n)
{
    return rt_sme_call(dst, (uintptr_t)src, n, (void *)g_apple_sme_memmove);
}
#endif

int main(void)
{
    unsigned total_fail = 0;
    int i;
    const char *no_color;

    no_color = getenv("NO_COLOR");
    if (no_color && no_color[0] != '\0')
        g_color = 0;
    {
        const char *term = getenv("TERM");
        if (term && strcmp(term, "dumb") == 0)
            g_color = 0;
    }

    printf("%srt host oracle%s — libc vs rt · one table per binary\n",
           g_color ? C_BOLD : "", g_color ? C_RESET : "");
#if defined(RT_TABLE_SCALAR)
    printf("binary: scalar  ·  vectorize: %s\n",
#if defined(RT_VECTORIZE)
           "on"
#else
           "off"
#endif
           );
#elif defined(RT_TABLE_NEON)
    printf("binary: neon\n");
#elif defined(RT_TABLE_SME)
    printf("binary: sme\n");
#elif defined(RT_TABLE_SIMD)
    printf("binary: simd\n");
#elif defined(RT_TABLE_RVV)
    printf("binary: rvv\n");
#endif

#if defined(__i386__) && !defined(__x86_64__)
    printf("host: i386");
    printf("  ·  backends: scalar i386");
    if (have_mmx()) printf(" mmx");
    if (have_sse()) printf(" sse");
    if (have_sse2()) printf(" sse2");
    printf("\n");
#elif defined(__x86_64__)
    printf("host: x86_64  ·  backends: scalar sse2");
    if (have_avx()) printf(" avx");
    if (have_avx2()) printf(" avx2");
    if (have_avx512()) printf(" avx512");
    printf("\n");
#elif defined(__riscv)
    printf("host: riscv%u  ·  libc: musl\n", (unsigned)__riscv_xlen);
#elif defined(__aarch64__) || defined(__arm64__)
    printf("host: ARM64");
#if !defined(RT_TABLE_SCALAR) && !defined(RT_TABLE_NEON) && !defined(RT_TABLE_SME)
    printf("  ·  backends: scalar neon");
#if defined(__APPLE__)
    printf(" sme");
#endif
    printf("  ·  SVE: not available on Apple Silicon (skipped)");
#endif
    printf("\n");
#else
    printf("host: unknown  ·  backends: scalar\n");
#endif

#if defined(__APPLE__) && defined(RT_RUN_SCALAR)
    g_apple_scalar_memset = map_apple_scalar_memset();
    g_apple_scalar_memmove = map_apple_scalar_memmove();
    if (!g_apple_scalar_memset || !apple_scalar_blob_ok(g_apple_scalar_memset) ||
        !g_apple_scalar_memmove || !apple_scalar_copy_ok(g_apple_scalar_memmove)) {
        fprintf(stderr, "apple scalar bodies not mapped\n");
        return 1;
    }
#endif
#if defined(__APPLE__) && defined(RT_RUN_SME)
    g_apple_sme_memset = dlsym(RTLD_DEFAULT, "__sme_memset");
    g_apple_sme_memcpy = dlsym(RTLD_DEFAULT, "__sme_memcpy");
    g_apple_sme_memmove = dlsym(RTLD_DEFAULT, "__sme_memmove");
    if (!g_apple_sme_memset || !g_apple_sme_memcpy || !g_apple_sme_memmove) {
        fprintf(stderr, "apple sme memory not mapped\n");
        return 1;
    }
#endif
#if defined(RT_RUN_SCALAR) && !defined(__riscv)
    run_mem_backend("scalar", rt_memcpy_scalar, rt_memmove_scalar,
                    rt_memset_scalar, rt_memcmp_scalar);
    run_strings();
    run_numeric();
    run_sort();
    run_format();
    run_alloc();
#endif

#if defined(__i386__) && !defined(__x86_64__)
#if defined(RT_RUN_SIMD)
    /* Pentium-era ladder: 386 REP → MMX → SSE (P3) */
    run_mem_backend("i386", rt_memcpy_i386, 0, rt_memset_i386, rt_memcmp_i386);
    if (have_mmx())
        run_mem_backend("mmx", rt_memcpy_mmx, 0, rt_memset_mmx, rt_memcmp_mmx);
    if (have_sse())
        run_mem_backend("sse", rt_memcpy_sse, 0, rt_memset_sse, rt_memcmp_sse);
#endif
#elif defined(__x86_64__)
#if defined(RT_RUN_SIMD)
    run_mem_backend("sse2", rt_memcpy_sse2, 0, rt_memset_sse2, rt_memcmp_sse2);
    if (have_avx())
        run_mem_backend("avx", rt_memcpy_avx, 0, rt_memset_avx, rt_memcmp_avx);
    if (have_avx2())
        run_mem_backend("avx2", rt_memcpy_avx2, 0, rt_memset_avx2, rt_memcmp_avx2);
    if (have_avx512())
        run_mem_backend("avx512", rt_memcpy_avx512, 0, rt_memset_avx512, rt_memcmp_avx512);
#endif
#elif defined(__aarch64__) || defined(__arm64__)
#if defined(RT_RUN_NEON)
    run_mem_backend("neon", rt_memcpy_neon, 0, rt_memset_neon, rt_memcmp_neon);
    run_strings_neon();
#endif
#if defined(__APPLE__) && defined(RT_RUN_SME)
    /* memcpy, memmove, and memset time __sme_* through rt_sme_call.
       Apple publishes no __sme_memcmp, so that row is live memcmp. */
    {
        struct row *nr = row_begin("memcpy", "sme", GRP_MEMORY);
        if (nr) bench_memcpy(nr, apple_sme_memcpy, rt_memcpy_sme);
    }
    {
        struct row *nr = row_begin("memmove", "sme", GRP_MEMORY);
        if (nr) bench_memmove(nr, apple_sme_memmove, rt_memmove_sme);
    }
    {
        struct row *nr = row_begin("memset", "sme", GRP_MEMORY);
        if (nr) bench_memset(nr, apple_sme_memset, rt_memset_sme, 1);
    }
    {
        struct row *nr = row_begin("memcmp", "sme", GRP_MEMORY);
        if (nr) bench_memcmp(nr, rt_memcmp_sme);
    }
#endif
#elif defined(__riscv)
#if defined(RT_RUN_SCALAR)
    run_mem_backend("scalar", rt_memcpy_scalar, rt_memmove_scalar,
                    rt_memset_scalar, rt_memcmp_scalar);
    run_strings_riscv();
#endif
#if defined(RT_RUN_RVV)
    run_mem_backend("rvv", rt_memcpy_rvv, 0, rt_memset_rvv, rt_memcmp_rvv);
    run_strings_riscv();
#endif
#endif

    print_report();
    for (i = 0; i < g_nrows; i++)
        total_fail += g_rows[i].fails;
    return total_fail ? 1 : 0;
}
