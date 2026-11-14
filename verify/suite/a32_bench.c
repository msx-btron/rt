/* Contract bench for one AArch32 kernel.
   Compile with -DRT_SUF=m0 (or m3, m4, m7, m33, m55, arm1176, a32).
   One plain-text table, same columns as the host oracle.
   strscpy, strscat, and strpad are rt.btron.pro: libc has no symbol.
   A cycle counter that does not advance leaves both time cells N/A.
   QEMU numbers are ticks, not silicon, and are not bench.html.
   -DRT_HOST uses CLOCK_MONOTONIC and the board libc. */
#ifdef RT_HOST
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
static void sh_write0(const char *s)
{
    fputs(s, stdout);
    fflush(stdout);
}
static void sh_exit(int code)
{
    exit(code);
}
#define libc_memcpy memcpy
#define libc_memset memset
#define libc_memcmp memcmp
#define libc_strlen strlen
#define libc_strnlen strnlen
#define libc_strcmp strcmp
#define RT_LIBC_MEMCPY 1
#define RT_LIBC_MEMSET 1
#define RT_LIBC_MEMCMP 1
#define RT_LIBC_STRLEN 1
#define RT_LIBC_STRNLEN 1
#define RT_LIBC_STRCMP 1
#else
#include <stddef.h>
extern void sh_write0(const char *s);
extern void sh_exit(int code);
#endif

#define CAT(a, b) a##b
#define XCAT(a, b) CAT(a, b)
#define FN(name) XCAT(name##_, RT_SUF)
#define STR2(x) #x
#define STR(x) STR2(x)

extern void sh_write0(const char *s);
extern void sh_exit(int code);

void *FN(rt_memcpy)(void *, const void *, size_t);
void *FN(rt_memset)(void *, int, size_t);
int FN(rt_memcmp)(const void *, const void *, size_t);
size_t FN(rt_strlen)(const char *);
size_t FN(rt_strnlen)(const char *, size_t);
char *FN(rt_strcpy)(char *, const char *);
char *FN(rt_strncpy)(char *, const char *, size_t);
char *FN(rt_strcat)(char *, const char *);
char *FN(rt_strncat)(char *, const char *, size_t);
int FN(rt_strcmp)(const char *, const char *);
int FN(rt_strncmp)(const char *, const char *, size_t);
char *FN(rt_strchr)(const char *, int);
char *FN(rt_strrchr)(const char *, int);
char *FN(rt_strstr)(const char *, const char *);
char *FN(rt_strpbrk)(const char *, const char *);
size_t FN(rt_strscpy)(char *, const char *, size_t);
size_t FN(rt_strscat)(char *, const char *, size_t);
void FN(rt_strpad)(char *, const char *, size_t, int);

static unsigned checks, fails, shown;

enum { NROW = 18 };

static const char *const row_name[NROW] = {
    "memcpy", "memset", "memcmp",
    "strlen", "strnlen", "strcpy", "strncpy",
    "strcat", "strncat", "strcmp", "strncmp",
    "strchr", "strrchr", "strstr", "strpbrk",
    "strscpy", "strscat", "strpad"
};

static unsigned row_checks[NROW];
static unsigned row_fails[NROW];
static unsigned row_libc[NROW];
static unsigned row_rt[NROW];
static unsigned char row_has_libc[NROW];
static unsigned char row_timed[NROW];

static int prefix(const char *s, const char *p)
{
    while (*p) {
        if (*s++ != *p++)
            return 0;
    }
    return 1;
}

static int row_of(const char *msg)
{
    static const char *const pfx[] = {
        "strscpy", "strscat", "strpad",
        "strnlen", "strncpy", "strncat", "strncmp",
        "strrchr", "strchr", "strstr", "strpbrk",
        "strlen", "strcpy", "strcat", "strcmp",
        "memcpy", "memset", "memcmp"
    };
    static const unsigned id[] = {
        15, 16, 17, 4, 6, 8, 10, 12, 11, 13, 14, 3, 5, 7, 9, 0, 1, 2
    };
    unsigned i;
    for (i = 0; i < sizeof pfx / sizeof pfx[0]; i++) {
        if (prefix(msg, pfx[i]))
            return (int)id[i];
    }
    return -1;
}

static void put_u(unsigned n)
{
    static const unsigned p[10] = {
        1000000000u, 100000000u, 10000000u, 1000000u, 100000u,
        10000u, 1000u, 100u, 10u, 1u
    };
    char b[16];
    unsigned i, k = 0, started = 0;
    if (n == 0) {
        sh_write0("0");
        return;
    }
    for (i = 0; i < 10; i++) {
        unsigned d = 0;
        while (n >= p[i]) {
            n -= p[i];
            d++;
        }
        if (d || started) {
            b[k++] = (char)('0' + d);
            started = 1;
        }
    }
    b[k] = 0;
    sh_write0(b);
}

static void expect(int cond, const char *msg)
{
    int row = row_of(msg);
    checks++;
    if (row >= 0)
        row_checks[row]++;
    if (cond)
        return;
    fails++;
    if (row >= 0)
        row_fails[row]++;
    if (shown < 20) {
        sh_write0("FAIL ");
        put_u(checks);
        sh_write0(" ");
        sh_write0(msg);
        sh_write0("\n");
        shown++;
    }
}

static void fill(unsigned char *p, unsigned n, unsigned char v)
{
    unsigned i;
    for (i = 0; i < n; i++)
        p[i] = v;
}

static int same(const unsigned char *a, const unsigned char *b, unsigned n)
{
    unsigned i;
    for (i = 0; i < n; i++)
        if (a[i] != b[i])
            return 0;
    return 1;
}

static int refcmp(const unsigned char *a, const unsigned char *b, unsigned n)
{
    unsigned i;
    for (i = 0; i < n; i++)
        if (a[i] != b[i])
            return (int)a[i] - (int)b[i];
    return 0;
}

static unsigned slen(const char *s)
{
    unsigned n = 0;
    while (s[n])
        n++;
    return n;
}

static int scmp(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

static unsigned char raw[384];
static char sbuf[384];
#ifdef RT_HOST
static unsigned char page[8192] __attribute__((aligned(4096)));
#else
static unsigned char page[8192] __attribute__((aligned(4096), section(".bss.page")));
#endif

static const unsigned lens[] = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 17, 31, 32, 33, 47, 48, 63, 64, 65, 80
};

static void test_mem(void)
{
    unsigned li, da, sa, n, i;
    unsigned char *dst, *src, *guard;

    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        n = lens[li];
        for (da = 0; da < 8; da++) {
            for (sa = 0; sa < 8; sa += (da == 0 ? 1 : 7)) {
                dst = raw + 16 + da;
                src = raw + 160 + sa;
                guard = raw;
                fill(guard, 384, 0xa5);
                for (i = 0; i < n; i++)
                    src[i] = (unsigned char)(i * 17u + 3u + sa);
                expect(FN(rt_memcpy)(dst, src, n) == dst, "memcpy ret");
                expect(same(dst, src, n), "memcpy");
                expect(guard[15 + da] == 0xa5 && dst[n] == 0xa5, "memcpy canary");
            }
        }
    }
    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        n = lens[li];
        for (da = 0; da < 8; da++) {
            static const int vals[] = {0, 1, 0x7f, 0x80, 0xff, 0x1ff};
            unsigned vi;
            for (vi = 0; vi < 6; vi++) {
                dst = raw + 16 + da;
                fill(raw, 384, 0xa5);
                expect(FN(rt_memset)(dst, vals[vi], n) == dst, "memset ret");
                for (i = 0; i < n; i++)
                    if (dst[i] != (unsigned char)vals[vi])
                        break;
                expect(i == n, "memset");
                expect(raw[15 + da] == 0xa5 && dst[n] == 0xa5, "memset canary");
            }
        }
    }
    expect(FN(rt_memcmp)(raw, raw, 0) == 0, "memcmp 0");
    for (n = 0; n <= 64; n++) {
        fill(raw, 128, 0);
        fill(raw + 128, 128, 0);
        for (i = 0; i < n; i++) {
            raw[i] = (unsigned char)(i + 1);
            raw[128 + i] = (unsigned char)(i + 1);
        }
        expect(FN(rt_memcmp)(raw, raw + 128, n) == 0, "memcmp eq");
        if (n) {
            raw[n - 1] ^= 0x80;
            expect(FN(rt_memcmp)(raw, raw + 128, n) == refcmp(raw, raw + 128, n), "memcmp ne");
            raw[0] = 0x00;
            raw[128] = 0xff;
            expect(FN(rt_memcmp)(raw, raw + 128, n) == refcmp(raw, raw + 128, n), "memcmp sign");
        }
    }
}

static void put_at(char *d, unsigned off, const char *s)
{
    unsigned i;
    for (i = 0; i < off; i++)
        d[i] = 'X';
    for (i = 0; s[i]; i++)
        d[off + i] = s[i];
    d[off + i] = 0;
}

static void test_strings(void)
{
    static const char *samples[] = {
        "", "a", "ab", "abc", "abcd", "abcde", "hello",
        "0123456789abcdef", "0123456789abcdefG",
        "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", "\x80\xff\x01"
    };
    unsigned si, off, n, i;
    char *s, *d, *p;

    for (si = 0; si < sizeof samples / sizeof samples[0]; si++) {
        n = slen(samples[si]);
        for (off = 0; off < 8; off++) {
            fill((unsigned char *)sbuf, sizeof sbuf, 0xa5);
            put_at(sbuf, off, samples[si]);
            s = sbuf + off;
            expect(FN(rt_strlen)(s) == n, "strlen");
            expect(FN(rt_strnlen)(s, 0) == 0, "strnlen 0");
            expect(FN(rt_strnlen)(s, n) == n, "strnlen n");
            expect(FN(rt_strnlen)(s, n + 5) == n, "strnlen big");
            if (n)
                expect(FN(rt_strnlen)(s, n - 1) == n - 1, "strnlen short");

            d = sbuf + 128;
            fill((unsigned char *)d, 80, 0xa5);
            expect(FN(rt_strcpy)(d, s) == d, "strcpy ret");
            expect(scmp(d, s) == 0 && d[n] == 0, "strcpy");

            fill((unsigned char *)d, 80, 0xa5);
            FN(rt_strncpy)(d, s, 0);
            expect(d[0] == (char)0xa5, "strncpy 0");
            FN(rt_strncpy)(d, s, n + 3);
            expect(scmp(d, s) == 0, "strncpy");
            for (i = n; i < n + 3; i++)
                if (d[i] != 0)
                    break;
            expect(i == n + 3, "strncpy pad");

            fill((unsigned char *)d, 80, 0);
            d[0] = 'Q';
            d[1] = 0;
            expect(FN(rt_strcat)(d, s) == d, "strcat ret");
            expect(d[0] == 'Q' && scmp(d + 1, s) == 0, "strcat");

            fill((unsigned char *)d, 80, 0);
            d[0] = 'Q';
            d[1] = 0;
            FN(rt_strncat)(d, s, 0);
            expect(d[0] == 'Q' && d[1] == 0, "strncat 0");
            FN(rt_strncat)(d, "xyz", 2);
            expect(scmp(d, "Qxy") == 0, "strncat");

            expect(FN(rt_strcmp)(s, s) == 0, "strcmp eq");
            expect(FN(rt_strncmp)("abc", "abd", 0) == 0, "strncmp 0");
            expect(FN(rt_strncmp)("abc", "abd", 2) == 0, "strncmp 2");
            expect(FN(rt_strncmp)("abc", "abd", 3) == scmp("abc", "abd"), "strncmp 3");

            if (n) {
                p = FN(rt_strchr)(s, (unsigned char)s[0]);
                expect(p == s, "strchr");
                p = FN(rt_strchr)(s, 0);
                expect(p == s + n, "strchr nul");
                expect(FN(rt_strchr)(s, 'Q') == 0, "strchr miss");
                expect(FN(rt_strrchr)(s, (unsigned char)s[n - 1]) != 0, "strrchr");
            } else {
                expect(FN(rt_strchr)(s, 0) == s, "strchr empty");
                expect(FN(rt_strrchr)(s, 0) == s, "strrchr empty");
            }
            expect(FN(rt_strstr)(s, "") == s, "strstr empty");
            expect(FN(rt_strstr)(s, s) == s, "strstr self");
            expect(FN(rt_strpbrk)(s, "") == 0, "strpbrk empty");

            fill((unsigned char *)d, 80, 0xa5);
            expect(FN(rt_strscpy)(d, s, 0) == n && d[0] == (char)0xa5, "strscpy 0");
            expect(FN(rt_strscpy)(d, s, 1) == n && d[0] == 0, "strscpy 1");
            expect(FN(rt_strscpy)(d, s, n + 1) == n && scmp(d, s) == 0, "strscpy");

            fill((unsigned char *)d, 80, 0);
            expect(FN(rt_strscat)(d, s, 0) == n, "strscat 0");
            expect(FN(rt_strscat)(d, s, n + 1) == n && scmp(d, s) == 0, "strscat");

            FN(rt_strpad)(d, "ab", 4, 0x80);
            expect(d[0] == 'a' && d[1] == 'b' && d[2] == (char)0x80 && d[3] == (char)0x80, "strpad");
        }
    }
    expect(FN(rt_strcmp)("abc", "abd") == scmp("abc", "abd"), "strcmp");
    expect(FN(rt_strcmp)("abd", "abc") == scmp("abd", "abc"), "strcmp 2");
    expect(FN(rt_strcmp)("", "a") < 0 && FN(rt_strcmp)("a", "") > 0, "strcmp empty");
    {
        char *h = sbuf + 200;
        put_at(h, 0, "aaaa");
        expect(FN(rt_strstr)(h, "aaa") == h, "strstr aaa");
        put_at(h, 0, "xxabcyy");
        expect(FN(rt_strstr)(h, "abc") == h + 2, "strstr mid");
        expect(FN(rt_strstr)(h, "zzz") == 0, "strstr miss");
        expect(FN(rt_strpbrk)(h, "c") == h + 4, "strpbrk");
        put_at(h, 0, "abaca");
        expect(FN(rt_strrchr)(h, 'a') == h + 4, "strrchr last");
        expect(FN(rt_strchr)(h, 0x161) == h, "strchr trunc");
    }
}

static void test_page(void)
{
    char *s = (char *)page + 4096 - 20;
    char *d = sbuf;
    unsigned i;
    for (i = 0; i < 18; i++)
        s[i] = (char)('a' + (i % 26));
    s[18] = 0;
    s[19] = 0x5a;
    expect(FN(rt_strlen)(s) == 18, "strlen page");
    fill((unsigned char *)d, 40, 0xa5);
    FN(rt_strcpy)(d, s);
    expect(slen(d) == 18 && d[18] == 0 && d[19] == (char)0xa5, "strcpy page");
    expect(FN(rt_strcmp)(s, d) == 0, "strcmp page");
    expect(FN(rt_strchr)(s, 'a') == s, "strchr page");
    s = (char *)page + 4096 - 2;
    s[0] = 'h';
    s[1] = 0;
    expect(FN(rt_strlen)(s) == 1, "strlen edge");
}

#ifdef RT_CPACR
static void enable_mve(void)
{
    volatile unsigned *cpacr = (volatile unsigned *)0xE000ED88;
    *cpacr |= 0x00F00000u;
    __asm__ volatile("dsb");
    __asm__ volatile("isb");
}
#endif

#ifndef RT_HOST
#ifdef RT_LIBC_MEMCPY
void *libc_memcpy(void *, const void *, size_t);
#endif
#ifdef RT_LIBC_MEMSET
void *libc_memset(void *, int, size_t);
#endif
#ifdef RT_LIBC_MEMCMP
int libc_memcmp(const void *, const void *, size_t);
#endif
#ifdef RT_LIBC_STRLEN
size_t libc_strlen(const char *);
#endif
#ifdef RT_LIBC_STRNLEN
size_t libc_strnlen(const char *, size_t);
#endif
#ifdef RT_LIBC_STRCMP
int libc_strcmp(const char *, const char *);
#endif
#endif

static unsigned cycles(void)
{
#if defined(RT_PMU)
    unsigned v;
    __asm__ volatile("mrc p15, 0, %0, c9, c13, 0" : "=r"(v));
    return v;
#elif defined(RT_PMU6)
    unsigned v;
    __asm__ volatile("mrc p15, 0, %0, c15, c12, 1" : "=r"(v));
    return v;
#elif defined(RT_DWT)
    return *(volatile unsigned *)0xE0001004u;
#elif defined(RT_HOST)
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0;
    return (unsigned)(ts.tv_sec * 1000000000ull + (unsigned long long)ts.tv_nsec);
#else
    return 0;
#endif
}

static int clock_live(void)
{
    volatile unsigned sink = 0;
    unsigned a, b, i;
    a = cycles();
    for (i = 0; i < 1000u; i++)
        sink += i;
    b = cycles();
    (void)sink;
    return a != b;
}

static unsigned median(unsigned *v, unsigned n)
{
    unsigned i, j, t;
    for (i = 1; i < n; i++) {
        t = v[i];
        j = i;
        while (j > 0 && v[j - 1] > t) {
            v[j] = v[j - 1];
            j--;
        }
        v[j] = t;
    }
    return v[n / 2];
}

enum { WARM = 16, SAMPLES = 21, ITER_MEM = 256, ITER_STR = 1024 };

static void take(unsigned row, int has, unsigned *lc, unsigned *rt)
{
    row_rt[row] = median(rt, SAMPLES);
    row_timed[row] = 1;
    if (has && row < 15) {
        row_libc[row] = median(lc, SAMPLES);
        row_has_libc[row] = 1;
    }
}

static void time_all(void)
{
    unsigned char *dst = page;
    unsigned char *src = page + 4096;
    unsigned lc[SAMPLES], rt[SAMPLES], si, k, i;
    volatile unsigned sink = 0;
    char *s = (char *)page;
    char *d = (char *)page + 1200;
    char *b = (char *)page + 2400;

    if (!clock_live())
        return;

    for (i = 0; i < 4096; i++)
        src[i] = (unsigned char)(i * 17u + 3u);
    for (k = 0; k < WARM; k++)
        sink += (unsigned)(size_t)FN(rt_memcpy)(dst, src, 4096);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
#ifdef RT_LIBC_MEMCPY
        for (k = 0; k < ITER_MEM; k++)
            sink += (unsigned)(size_t)libc_memcpy(dst, src, 4096);
        lc[si] = cycles() - t0;
        t0 = cycles();
#endif
        for (k = 0; k < ITER_MEM; k++)
            sink += (unsigned)(size_t)FN(rt_memcpy)(dst, src, 4096);
        rt[si] = cycles() - t0;
    }
#ifdef RT_LIBC_MEMCPY
    take(0, 1, lc, rt);
#else
    take(0, 0, lc, rt);
#endif

    for (k = 0; k < WARM; k++)
        sink += (unsigned)(size_t)FN(rt_memset)(dst, 0xa5, 4096);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
#ifdef RT_LIBC_MEMSET
        for (k = 0; k < ITER_MEM; k++)
            sink += (unsigned)(size_t)libc_memset(dst, 0xa5, 4096);
        lc[si] = cycles() - t0;
        t0 = cycles();
#endif
        for (k = 0; k < ITER_MEM; k++)
            sink += (unsigned)(size_t)FN(rt_memset)(dst, 0xa5, 4096);
        rt[si] = cycles() - t0;
    }
#ifdef RT_LIBC_MEMSET
    take(1, 1, lc, rt);
#else
    take(1, 0, lc, rt);
#endif

    FN(rt_memcpy)(dst, src, 4096);
    for (k = 0; k < WARM; k++)
        sink += (unsigned)FN(rt_memcmp)(dst, src, 4096);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
#ifdef RT_LIBC_MEMCMP
        for (k = 0; k < ITER_MEM; k++)
            sink += (unsigned)libc_memcmp(dst, src, 4096);
        lc[si] = cycles() - t0;
        t0 = cycles();
#endif
        for (k = 0; k < ITER_MEM; k++)
            sink += (unsigned)FN(rt_memcmp)(dst, src, 4096);
        rt[si] = cycles() - t0;
    }
#ifdef RT_LIBC_MEMCMP
    take(2, 1, lc, rt);
#else
    take(2, 0, lc, rt);
#endif

    for (i = 0; i < 1024; i++)
        s[i] = (char)('a' + (i % 26));
    s[1024] = 0;
    for (i = 0; i < 255; i++)
        b[i] = s[i];
    b[200] = 'z';
    b[255] = 0;

    for (k = 0; k < WARM; k++)
        sink += FN(rt_strlen)(s);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
#ifdef RT_LIBC_STRLEN
        for (k = 0; k < ITER_STR; k++)
            sink += libc_strlen(s);
        lc[si] = cycles() - t0;
        t0 = cycles();
#endif
        for (k = 0; k < ITER_STR; k++)
            sink += FN(rt_strlen)(s);
        rt[si] = cycles() - t0;
    }
#ifdef RT_LIBC_STRLEN
    take(3, 1, lc, rt);
#else
    take(3, 0, lc, rt);
#endif

    for (k = 0; k < WARM; k++)
        sink += FN(rt_strnlen)(s, 2048);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
#ifdef RT_LIBC_STRNLEN
        for (k = 0; k < ITER_STR; k++)
            sink += libc_strnlen(s, 2048);
        lc[si] = cycles() - t0;
        t0 = cycles();
#endif
        for (k = 0; k < ITER_STR; k++)
            sink += FN(rt_strnlen)(s, 2048);
        rt[si] = cycles() - t0;
    }
#ifdef RT_LIBC_STRNLEN
    take(4, 1, lc, rt);
#else
    take(4, 0, lc, rt);
#endif

    for (k = 0; k < WARM; k++)
        sink += (unsigned)(size_t)FN(rt_strcpy)(d, s);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)(size_t)FN(rt_strcpy)(d, s);
        rt[si] = cycles() - t0;
    }
    take(5, 0, lc, rt);

    for (k = 0; k < WARM; k++)
        FN(rt_strncpy)(d, s, 512);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            FN(rt_strncpy)(d, s, 512);
        rt[si] = cycles() - t0;
    }
    take(6, 0, lc, rt);

    d[0] = 'Q';
    d[1] = 0;
    for (k = 0; k < WARM; k++) {
        d[1] = 0;
        sink += (unsigned)(size_t)FN(rt_strcat)(d, "abcdef");
    }
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++) {
            d[1] = 0;
            sink += (unsigned)(size_t)FN(rt_strcat)(d, "abcdef");
        }
        rt[si] = cycles() - t0;
    }
    take(7, 0, lc, rt);

    for (k = 0; k < WARM; k++) {
        d[1] = 0;
        FN(rt_strncat)(d, s, 32);
    }
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++) {
            d[1] = 0;
            FN(rt_strncat)(d, s, 32);
        }
        rt[si] = cycles() - t0;
    }
    take(8, 0, lc, rt);

    for (k = 0; k < WARM; k++)
        sink += (unsigned)FN(rt_strcmp)(s, b);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
#ifdef RT_LIBC_STRCMP
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)libc_strcmp(s, b);
        lc[si] = cycles() - t0;
        t0 = cycles();
#endif
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)FN(rt_strcmp)(s, b);
        rt[si] = cycles() - t0;
    }
#ifdef RT_LIBC_STRCMP
    take(9, 1, lc, rt);
#else
    take(9, 0, lc, rt);
#endif

    for (k = 0; k < WARM; k++)
        sink += (unsigned)FN(rt_strncmp)(s, b, 255);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)FN(rt_strncmp)(s, b, 255);
        rt[si] = cycles() - t0;
    }
    take(10, 0, lc, rt);

    s[400] = 'Z';
    for (k = 0; k < WARM; k++)
        sink += (unsigned)(size_t)FN(rt_strchr)(s, 'Z');
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)(size_t)FN(rt_strchr)(s, 'Z');
        rt[si] = cycles() - t0;
    }
    take(11, 0, lc, rt);

    for (k = 0; k < WARM; k++)
        sink += (unsigned)(size_t)FN(rt_strrchr)(s, 'a');
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)(size_t)FN(rt_strrchr)(s, 'a');
        rt[si] = cycles() - t0;
    }
    take(12, 0, lc, rt);

    for (k = 0; k < WARM; k++)
        sink += (unsigned)(size_t)FN(rt_strstr)(s, "Za");
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)(size_t)FN(rt_strstr)(s, "Za");
        rt[si] = cycles() - t0;
    }
    take(13, 0, lc, rt);

    for (k = 0; k < WARM; k++)
        sink += (unsigned)(size_t)FN(rt_strpbrk)(s, "Z");
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            sink += (unsigned)(size_t)FN(rt_strpbrk)(s, "Z");
        rt[si] = cycles() - t0;
    }
    take(14, 0, lc, rt);

    for (k = 0; k < WARM; k++)
        sink += FN(rt_strscpy)(d, s, 512);
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            sink += FN(rt_strscpy)(d, s, 512);
        rt[si] = cycles() - t0;
    }
    take(15, 0, lc, rt);

    for (k = 0; k < WARM; k++) {
        d[0] = 0;
        sink += FN(rt_strscat)(d, s, 512);
    }
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++) {
            d[0] = 0;
            sink += FN(rt_strscat)(d, s, 512);
        }
        rt[si] = cycles() - t0;
    }
    take(16, 0, lc, rt);

    for (k = 0; k < WARM; k++)
        FN(rt_strpad)(d, s, 256, ' ');
    for (si = 0; si < SAMPLES; si++) {
        unsigned t0 = cycles();
        for (k = 0; k < ITER_STR; k++)
            FN(rt_strpad)(d, s, 256, ' ');
        rt[si] = cycles() - t0;
    }
    take(17, 0, lc, rt);
    (void)sink;
}

static unsigned udiv(unsigned n, unsigned d)
{
    unsigned q = 0, r = 0, i;
    if (d == 0)
        return 0;
    for (i = 0; i < 32; i++) {
        r = (r << 1) | (n >> 31);
        n <<= 1;
        q <<= 1;
        if (r >= d) {
            r -= d;
            q |= 1;
        }
    }
    return q;
}

static void fmt_u(char *b, unsigned n, unsigned *len)
{
    static const unsigned p[10] = {
        1000000000u, 100000000u, 10000000u, 1000000u, 100000u,
        10000u, 1000u, 100u, 10u, 1u
    };
    unsigned i, k = 0, started = 0;
    if (n == 0) {
        b[0] = '0';
        b[1] = 0;
        *len = 1;
        return;
    }
    for (i = 0; i < 10; i++) {
        unsigned dig = 0;
        while (n >= p[i]) {
            n -= p[i];
            dig++;
        }
        if (dig || started) {
            b[k++] = (char)('0' + dig);
            started = 1;
        }
    }
    b[k] = 0;
    *len = k;
}

static void put_sp(unsigned n)
{
    static const char sp[] = "                ";
    if (n > 16)
        n = 16;
    sh_write0(sp + (16 - n));
}

static void put_field(unsigned n, unsigned width)
{
    char b[16];
    unsigned len;
    fmt_u(b, n, &len);
    if (len < width)
        put_sp(width - len);
    sh_write0(b);
}

static void put_coef(unsigned libc_n, unsigned rt_n)
{
    unsigned q, rem, h, whole, frac, tens;
    char b[16];
    unsigned len, i;
    if (rt_n == 0) {
        sh_write0("       N/A");
        return;
    }
    q = udiv(libc_n, rt_n);
    rem = libc_n - q * rt_n;
    /* rem < rt_n, so rem*100 can exceed 32 bits. Add rem, one hundred times. */
    h = 0;
    {
        unsigned acc = 0, step;
        for (step = 0; step < 100u; step++) {
            if (rem != 0 && acc >= rt_n - rem) {
                acc = acc + rem - rt_n;
                h++;
            } else {
                acc += rem;
            }
        }
    }
    h += q * 100u;
    whole = udiv(h, 100u);
    frac = h - whole * 100u;
    fmt_u(b, whole, &len);
    b[len++] = '.';
    tens = 0;
    while (frac >= 10) {
        frac -= 10;
        tens++;
    }
    b[len++] = (char)('0' + tens);
    b[len++] = (char)('0' + frac);
    b[len] = 0;
    if (len < 10)
        put_sp(10 - len);
    for (i = 0; i < len; i++) {
        char one[2];
        one[0] = b[i];
        one[1] = 0;
        sh_write0(one);
    }
}

static void put_name(const char *s)
{
    unsigned n = 0;
    while (s[n])
        n++;
    sh_write0(s);
    if (n < 16)
        put_sp(16 - n);
}

static void put_backend(void)
{
#if defined(RT_A_PROFILE)
    unsigned midr, part;
    __asm__ volatile("mrc p15, 0, %0, c0, c0, 0" : "=r"(midr));
    part = (midr >> 4) & 0xfffu;
    if (part == 0xc07u)
        sh_write0("a32-a7");
    else if (part == 0xc0fu)
        sh_write0("a32-a15");
    else if (part == 0xd03u)
        sh_write0("a32-a53");
    else if (part == 0xd08u)
        sh_write0("a32-a72");
    else if (part == 0xb76u)
        sh_write0("arm1176");
    else
        sh_write0(STR(RT_SUF));
#else
    sh_write0(STR(RT_SUF));
#endif
}

static void print_table(void)
{
    unsigned i, tc = 0, tf = 0;
    const char *bar =
        "+------------------+----------+----------+--------+------+------------+\n";
    sh_write0("\n== backend: ");
    put_backend();
    sh_write0(" ==\n");
    sh_write0("legend: coef = libc_ns/rt_ns · median of 21 samples · 1.00 = parity · N/A = no libc symbol or a stuck counter\n");
    sh_write0("strscpy, strscat, strpad are rt.btron.pro and have no libc symbol\n");
#if defined(RT_HOST)
    sh_write0("baseline: board libc\n");
#elif defined(RT_PMU) || defined(RT_PMU6)
    sh_write0("baseline: Arm Optimized Routines v25.01\n");
#elif defined(RT_LIBC_MEMCPY) || defined(RT_LIBC_MEMSET) || defined(RT_LIBC_STRLEN) || defined(RT_LIBC_STRNLEN)
    sh_write0("baseline: picolibc 1.8.10\n");
#else
    sh_write0("baseline: none\n");
#endif
    sh_write0(bar);
    sh_write0("| function         | libc ns  | rt ns    | checks | fail | coef       |\n");
    sh_write0(bar);
    for (i = 0; i < NROW; i++) {
        sh_write0("| ");
        put_name(row_name[i]);
        sh_write0(" | ");
        if (!row_timed[i] || !row_has_libc[i])
            sh_write0("     N/A");
        else
            put_field(row_libc[i], 8);
        sh_write0(" | ");
        if (!row_timed[i] || row_rt[i] == 0)
            sh_write0("     N/A");
        else
            put_field(row_rt[i], 8);
        sh_write0(" | ");
        put_field(row_checks[i], 6);
        sh_write0(" | ");
        put_field(row_fails[i], 4);
        sh_write0(" | ");
        if (!row_timed[i] || !row_has_libc[i] || row_rt[i] == 0)
            sh_write0("       N/A");
        else
            put_coef(row_libc[i], row_rt[i]);
        sh_write0(" |\n");
        tc += row_checks[i];
        tf += row_fails[i];
    }
    sh_write0(bar);
    sh_write0("| TOTAL            |          |          | ");
    put_field(tc, 6);
    sh_write0(" | ");
    put_field(tf, 4);
    sh_write0(" |            |\n");
    sh_write0(bar);
}

int main(void)
{
#ifdef RT_CPACR
    enable_mve();
#endif
    test_mem();
    test_strings();
    test_page();
    time_all();
    print_table();
    sh_write0("TOTAL checks ");
    put_u(checks);
    sh_write0(" fail ");
    put_u(fails);
    sh_write0("\n");
    sh_exit(fails ? 1 : 0);
    for (;;)
        ;
}
