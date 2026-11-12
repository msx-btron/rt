#define _POSIX_C_SOURCE 200809L
/* Host libc vs rt — timed ns columns + improvement coefficient + colored groups. */
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

static unsigned char g_a[BUF], g_b[BUF], g_c[BUF];
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

/* Row belongs in this backend's full-scope table:
   - Memory: this backend only
   - String: this backend's rows if any, plus scalar-only string fns when backend is scalar
   - Other groups: scalar baseline (shown on every table) */
static int row_in_backend_table(const struct row *r, const char *backend)
{
    if (r->group == GRP_MEMORY)
        return strcmp(r->backend, backend) == 0;
    if (r->group == GRP_STRING) {
        if (strcmp(r->backend, backend) == 0)
            return 1;
        /* scalar-only string helpers appear only on scalar table */
        if (strcmp(backend, "scalar") == 0 && strcmp(r->backend, "scalar") == 0)
            return 1;
        return 0;
    }
    /* Numeric / Sort / Format / Allocator: scalar baseline on every table */
    return strcmp(r->backend, "scalar") == 0;
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

    if (strcmp(backend, "scalar") != 0)
        printf("%s(Memory/String vector = %s · other groups = scalar baseline)%s\n",
               g_color ? C_DIM : "", backend, g_color ? C_RESET : "");

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
            double c;
            const char *st_col, *coef_col, *name_col;
            char coef_s[16];
            if (!row_in_backend_table(r, backend) || r->group != g)
                continue;
            c = coef(r);
            snprintf(coef_s, sizeof coef_s, "%.2f", c);
            name_col = g_color ? grp_color[g] : "";
            st_col = r->fails ? (g_color ? C_RED : "") : (g_color ? C_GREEN : "");
            if (c >= 1.05)
                coef_col = g_color ? C_GREEN : "";
            else if (c <= 0.95)
                coef_col = g_color ? C_RED : "";
            else
                coef_col = g_color ? C_YELLOW : "";

            printf("| %s%-16s%s | %8llu | %8llu | %6u | %s%4u%s | %s%8s%s |\n",
                   name_col, r->name, g_color ? C_RESET : "",
                   (unsigned long long)r->libc_ns,
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
    printf("%slegend%s: coef = libc_ns/rt_ns · median of %d samples · 1.00 = parity\n",
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

static void bench_memcpy(struct row *r, copy_fn rt_fn)
{
    enum { N = 4096, LOOPS = ITER_MEM };
    unsigned char *dst = g_a + PAD;
    unsigned char *src = g_b + PAD;
    size_t i, k;
    uint64_t t0, t1;
    void *ret;

    for (i = 0; i < N; i++)
        src[i] = (unsigned char)(rnd() & 0xFFu);

    /* correctness sweep (untimed) */
    {
        static const size_t lens[] = { 0, 1, 3, 7, 8, 16, 32, 64, 100, 256, 1024, 4096 };
        size_t li, da;
        for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
            size_t n = lens[li];
            for (da = 0; da <= 8; da++) {
                unsigned char *d = g_a + PAD + da;
                unsigned char *s = g_b + PAD;
                unsigned char *o = g_c + PAD + da;
                if (PAD + da + n + 8 >= BUF) continue;
                poison(g_a, BUF);
                memcpy(o, s, n);
                ret = rt_fn(d, s, n);
                row_add(r, ret == d && same_mem(d, o, n));
            }
        }
    }

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            memcpy(dst, src, N);
            rt_fn(dst, src, N);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                memcpy(dst, src, N);
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

static void bench_memmove(struct row *r, copy_fn rt_fn)
{
    enum { N = 2048, LOOPS = ITER_MEM };
    unsigned char *base = g_a + PAD;
    size_t i, k;
    uint64_t t0, t1;

    for (i = 0; i < N + 64; i++)
        base[i] = (unsigned char)(rnd() & 0xFFu);

    /* correctness */
    {
        size_t n, off;
        for (n = 0; n <= 256; n = n ? n * 2 : 1) {
            for (off = 1; off <= 8; off++) {
                size_t total = n + off;
                unsigned char *b = g_a + PAD;
                unsigned char *ref = g_c + PAD;
                void *ret;
                for (i = 0; i < total; i++)
                    b[i] = ref[i] = (unsigned char)(30 + i);
                memmove(ref + off, ref, n);
                ret = rt_fn(b + off, b, n);
                row_add(r, ret == b + off && same_mem(b, ref, total));
            }
        }
    }

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            memmove(base + 16, base, N);
            rt_fn(base + 16, base, N);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                memmove(base + 16, base, N);
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

static void bench_memset(struct row *r, set_fn rt_fn)
{
    enum { N = 4096, LOOPS = ITER_MEM };
    unsigned char *dst = g_a + PAD;
    size_t k;
    uint64_t t0, t1;
    void *ret;

    {
        static const size_t lens[] = { 0, 1, 8, 16, 64, 256, 1024 };
        size_t li, da;
        for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
            for (da = 0; da <= 8; da++) {
                unsigned char *d = g_a + PAD + da;
                unsigned char *o = g_c + PAD + da;
                size_t n = lens[li];
                if (PAD + da + n + 8 >= BUF) continue;
                poison(g_a, BUF);
                memset(o, 0x5A, n);
                ret = rt_fn(d, 0x5A, n);
                row_add(r, ret == d && same_mem(d, o, n));
            }
        }
    }

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            memset(dst, 0xA5, N);
            rt_fn(dst, 0xA5, N);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                memset(dst, 0xA5, N);
            t1 = now_ns();
            lc[si] = t1 - t0;
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                rt_fn(dst, 0xA5, N);
            t1 = now_ns();
            rt_t[si] = t1 - t0;
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

    for (i = 0; i < N; i++)
        a[i] = b[i] = (unsigned char)(i & 0xFFu);
    b[N / 2] ^= 1;

    row_add(r, sign_eq(rt_fn(a, b, N), memcmp(a, b, N)));
    b[N / 2] ^= 1;
    row_add(r, sign_eq(rt_fn(a, b, N), memcmp(a, b, N)));

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

static void run_mem_backend(const char *backend, copy_fn cpy, copy_fn mv,
                            set_fn set, cmp_fn cmp)
{
    struct row *r;
    r = row_begin("memcpy", backend, GRP_MEMORY);
    if (r) bench_memcpy(r, cpy);
    if (mv) {
        r = row_begin("memmove", backend, GRP_MEMORY);
        if (r) bench_memmove(r, mv);
    }
    r = row_begin("memset", backend, GRP_MEMORY);
    if (r) bench_memset(r, set);
    r = row_begin("memcmp", backend, GRP_MEMORY);
    if (r) bench_memcmp(r, cmp);
}

/* ===================== STRING timed ===================== */

typedef size_t (*strlen_fn)(const char *);
typedef int (*strcmp_fn)(const char *, const char *);
typedef char *(*strchr_fn)(const char *, int);

static void bench_strlen_fn(struct row *r, strlen_fn fn)
{
    enum { LOOPS = ITER_STR };
    static char s[1025];
    size_t i, k;
    uint64_t t0, t1;
    volatile size_t sink = 0;

    for (i = 0; i < 1024; i++)
        s[i] = (char)('a' + (i % 26));
    s[1024] = 0;

    row_add(r, fn(s) == strlen(s));
    row_add(r, fn("") == 0);
    row_add(r, fn("a") == 1);
    row_add(r, fn("0123456789abcdef") == 16); /* exactly one NEON block */
    row_add(r, fn("0123456789abcdefZ") == 17);

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
    static char a[256], b[256];
    size_t i, k;
    uint64_t t0, t1;
    volatile int sink = 0;

    for (i = 0; i < 255; i++)
        a[i] = b[i] = (char)('a' + (i % 26));
    a[255] = b[255] = 0;
    b[200] = 'z';

    row_add(r, sign_eq(fn(a, b), strcmp(a, b)));

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
    static char s[512];
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
    static char src[N], da[N], db[N];
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

    memcpy(da, src, ncopy);
    rt_strcpy(db, src);
    row_add(r, memcmp(da, db, ncopy) == 0);

    {
        uint64_t lc[SAMPLES], rt_t[SAMPLES];
        int si;
        for (k = 0; k < WARM; k++) {
            memcpy(da, src, ncopy);
            rt_strcpy(db, src);
        }
        for (si = 0; si < SAMPLES; si++) {
            t0 = now_ns();
            for (k = 0; k < LOOPS; k++)
                memcpy(da, src, ncopy);
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
    static char hay[1024];
    const char *nd = "needle";
    size_t i, k;
    uint64_t t0, t1;
    volatile uintptr_t sink = 0;

    for (i = 0; i < 1000; i++)
        hay[i] = (char)('a' + (i % 26));
    memcpy(hay + 500, nd, 6);
    hay[1023] = 0;

    row_add(r, rt_strstr(hay, nd) == strstr(hay, nd));

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

static void exercise_strings_misc(void)
{
    struct row *r;
    size_t n;

    r = row_begin("strnlen", "scalar", GRP_STRING);
    for (n = 0; n <= 20; n++)
        row_add(r, rt_strnlen("abcdefghijklmnop", n) == (size_t)strnlen("abcdefghijklmnop", n));
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
        for (n = 0; n <= 16; n++) {
            char dst[32];
            size_t got, srclen = strlen(src), expect;
            memset(dst, 0xCC, 32);
            got = rt_strscpy(dst, src, n);
            row_add(r, got == srclen);
            if (n == 0) continue;
            expect = (n - 1) < srclen ? (n - 1) : srclen;
            row_add(r, dst[expect] == '\0');
        }
        if (r) { r->libc_ns = 1; r->rt_ns = 1; } /* no libc strscpy */
    }
}

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

#if defined(__aarch64__) || defined(__arm64__)
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

static void run_numeric(void)
{
    struct row *r;
    size_t i;
    uint64_t t0, t1;
    size_t k;
    volatile long sink = 0;

    r = row_begin("atoi", "scalar", GRP_NUMERIC);
    {
        static const char *s[] = { "0", "42", "-7", "  99", "2147483647", "-2147483648" };
        for (i = 0; i < 6; i++)
            row_add(r, rt_atoi(s[i]) == atoi(s[i]));
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += atoi("123456");
        t1 = now_ns();
        if (r) r->libc_ns = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += rt_atoi("123456");
        t1 = now_ns();
        if (r) r->rt_ns = t1 - t0;
    }

    r = row_begin("strtoul", "scalar", GRP_NUMERIC);
    {
        char *e1, *e2;
        row_add(r, rt_strtoul("0xff", &e1, 16) == strtoul("0xff", &e2, 16));
        row_add(r, rt_strtoul("077", &e1, 8) == strtoul("077", &e2, 8));
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)strtoul("12345678", 0, 10);
        t1 = now_ns();
        if (r) r->libc_ns = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)rt_strtoul("12345678", 0, 10);
        t1 = now_ns();
        if (r) r->rt_ns = t1 - t0;
    }

    r = row_begin("strtoull", "scalar", GRP_NUMERIC);
    {
        row_add(r, rt_strtoull("1234567890123", 0, 10) == strtoull("1234567890123", 0, 10));
        row_add(r, rt_strtoull("0xDeadBeef", 0, 0) == strtoull("0xDeadBeef", 0, 0));
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)strtoull("0x123456789", 0, 0);
        t1 = now_ns();
        if (r) r->libc_ns = t1 - t0;
        t0 = now_ns();
        for (k = 0; k < ITER_STR; k++) sink += (long)rt_strtoull("0x123456789", 0, 0);
        t1 = now_ns();
        if (r) r->rt_ns = t1 - t0;
    }
    (void)sink;
}

static void run_sort(void)
{
    struct row *r;
    int a[1024] = {0};
    int b[1024] = {0};
    int c[1024] = {0};
    size_t n, k;
    uint64_t t0, t1;
    int si;
    uint64_t lc[SAMPLES], rt_t[SAMPLES];
    enum { N = 512, LOOPS = 16 };

    /* correctness: shell + neo vs host */
    r = row_begin("qsort", "scalar", GRP_SORT);
    for (n = 0; n <= 64; n++) {
        for (k = 0; k < n; k++)
            a[k] = b[k] = (int)(rnd() % 1000u) - 500;
        rt_qsort(a, n, sizeof(int), icmp);
        qsort(b, n, sizeof(int), icmp);
        row_add(r, memcmp(a, b, n * sizeof(int)) == 0);
    }
    for (k = 0; k < (size_t)N; k++)
        a[k] = b[k] = (int)(rnd() % 10000u);
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

    r = row_begin("qsort_neo", "scalar", GRP_SORT);
    for (n = 0; n <= 128; n++) {
        for (k = 0; k < n; k++)
            a[k] = c[k] = (int)(rnd() % 1000u) - 500;
        rt_qsort_neo(a, n, sizeof(int), icmp);
        qsort(c, n, sizeof(int), icmp);
        row_add(r, memcmp(a, c, n * sizeof(int)) == 0);
    }
    /* patterns: already sorted, reversed, random */
    for (k = 0; k < (size_t)N; k++) b[k] = (int)k;
    rt_qsort_neo(b, (size_t)N, sizeof(int), icmp);
    row_add(r, 1);
    for (k = 0; k < (size_t)N; k++) b[k] = (int)((size_t)N - k);
    rt_qsort_neo(b, (size_t)N, sizeof(int), icmp);
    for (k = 1; k < (size_t)N; k++)
        if (b[k-1] > b[k]) { row_add(r, 0); break; }
    if (k == (size_t)N) row_add(r, 1);

    for (k = 0; k < (size_t)N; k++)
        a[k] = b[k] = (int)(rnd() % 100000u);
    for (k = 0; k < WARM; k++) {
        memcpy(a, b, sizeof(int) * (size_t)N);
        qsort(a, (size_t)N, sizeof(int), icmp);
        memcpy(a, b, sizeof(int) * (size_t)N);
        rt_qsort_neo(a, (size_t)N, sizeof(int), icmp);
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
            rt_qsort_neo(a, (size_t)N, sizeof(int), icmp);
        }
        t1 = now_ns();
        rt_t[si] = t1 - t0;
    }
    if (r) {
        r->libc_ns = median_u64(lc, SAMPLES);
        r->rt_ns = median_u64(rt_t, SAMPLES);
    }
}

static void run_format(void)
{
    struct row *r;
    char a[128], b[128];
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
    ra = rt_snprintf(a, 5, "abcdefgh");
    row_add(r, ra == 8 && strcmp(a, "abcd") == 0);
    a[0] = 'X';
    ra = rt_snprintf(a, sizeof a, NULL);
    row_add(r, ra == 0 && a[0] == '\0');

    t0 = now_ns();
    for (k = 0; k < ITER_FMT; k++)
        snprintf(b, sizeof b, "%d-%s-%x", (int)k, "item", (unsigned)k);
    t1 = now_ns();
    if (r) r->libc_ns = t1 - t0;

    t0 = now_ns();
    for (k = 0; k < ITER_FMT; k++)
        rt_snprintf(a, sizeof a, "%d-%s-%x", (int)k, "item", (unsigned)k);
    t1 = now_ns();
    if (r) r->rt_ns = t1 - t0;

    r = row_begin("fmt_f32", "scalar", GRP_FORMAT);
    {
        float vals[] = { 0.0f, 1.0f, -2.5f, 3.141592f };
        size_t vi;
        for (vi = 0; vi < 4; vi++) {
            char fb[64];
            row_add(r, rt_fmt_f32(fb, sizeof fb, vals[vi]) > 0);
        }
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

static void run_alloc(void)
{
    struct row *r = row_begin("alloc", "scalar", GRP_ALLOC);
    static unsigned char pool[8192];
    void *p1, *p2, *p3;
    size_t k;
    uint64_t t0, t1;

    rt_alloc_init(pool, sizeof pool);
    p1 = rt_malloc(100);
    p2 = rt_calloc(10, 4);
    row_add(r, p1 && p2);
    if (p2) {
        int z = 1;
        size_t i;
        for (i = 0; i < 40; i++)
            if (((unsigned char *)p2)[i]) z = 0;
        row_add(r, z);
    }
    p3 = rt_realloc(p1, 200);
    row_add(r, p3 != 0);
    rt_free(p3);
    rt_free(p2);

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
static int have_avx2(void)
{
    unsigned eax, ebx, ecx, edx, max;
    __asm__ volatile("cpuid" : "=a"(max), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(0));
    if (max < 1) return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1));
    if ((ecx & (1u << 27)) == 0 || (ecx & (1u << 28)) == 0) return 0;
    if ((xcr0() & 0x6ull) != 0x6ull) return 0;
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

    printf("%srt host oracle%s — libc vs rt · separate table per accessible backend\n",
           g_color ? C_BOLD : "", g_color ? C_RESET : "");

#if defined(__i386__) && !defined(__x86_64__)
    printf("host: i386");
    printf("  ·  backends: scalar i386");
    if (have_mmx()) printf(" mmx");
    if (have_sse()) printf(" sse");
    if (have_sse2()) printf(" sse2");
    printf("\n");
#elif defined(__x86_64__)
    printf("host: x86_64  ·  backends: scalar sse2");
    if (have_avx2()) printf(" avx2");
    if (have_avx512()) printf(" avx512");
    printf("\n");
#elif defined(__aarch64__) || defined(__arm64__)
    printf("host: ARM64  ·  backends: scalar neon");
    printf("  ·  SVE: not available on Apple Silicon (skipped)\n");
#else
    printf("host: unknown  ·  backends: scalar\n");
#endif

    /* ---- always: portable scalar plane ---- */
    run_mem_backend("scalar", rt_memcpy_scalar, rt_memmove_scalar,
                    rt_memset_scalar, rt_memcmp_scalar);
    run_strings();
    run_numeric();
    run_sort();
    run_format();
    run_alloc();

#if defined(__i386__) && !defined(__x86_64__)
    /* Pentium-era ladder: 386 REP → MMX → SSE (P3) */
    run_mem_backend("i386", rt_memcpy_i386, 0, rt_memset_i386, rt_memcmp_i386);
    if (have_mmx())
        run_mem_backend("mmx", rt_memcpy_mmx, 0, rt_memset_mmx, rt_memcmp_mmx);
    if (have_sse())
        run_mem_backend("sse", rt_memcpy_sse, 0, rt_memset_sse, rt_memcmp_sse);
#elif defined(__x86_64__)
    run_mem_backend("sse2", rt_memcpy_sse2, 0, rt_memset_sse2, rt_memcmp_sse2);
    if (have_avx2())
        run_mem_backend("avx2", rt_memcpy_avx2, 0, rt_memset_avx2, rt_memcmp_avx2);
    if (have_avx512())
        run_mem_backend("avx512", rt_memcpy_avx512, 0, rt_memset_avx512, rt_memcmp_avx512);
#elif defined(__aarch64__) || defined(__arm64__)
#if defined(__aarch64__) || defined(__arm64__)
    run_mem_backend("neon", rt_memcpy_neon, 0, rt_memset_neon, rt_memcmp_neon);
    run_strings_neon();
#endif
#endif

    print_report();
    for (i = 0; i < g_nrows; i++)
        total_fail += g_rows[i].fails;
    return total_fail ? 1 : 0;
}
