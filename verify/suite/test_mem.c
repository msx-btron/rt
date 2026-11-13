/* C99 contract for the rt memory kernels.
   A later proof may treat a passing run as the spec:
   memcpy, memmove, and memset return dst, write exactly n bytes, and
   leave every other byte in the buffer alone. memset stores (unsigned char)c.
   memcmp returns only the sign of the first unsigned-byte difference and
   does not write; the magnitude is not part of the contract.
   libc is the reference for the bytes and the sign. A length that does not
   fit in the buffer fails the run. It is not a skipped success.
   x86-64: scalar + sse2/avx2/avx512. i386: scalar + rep/mmx/pc98.
   macOS arm64 (M4): scalar + NEON. memmove is scalar on every architecture.
*/
#include "rt/mem.h"

#include <stdio.h>
#include <string.h>
#include <stdint.h>

enum { PAD = 64, BUF = 8192 };

static unsigned char g_src[BUF];
static unsigned char g_dst[BUF];
static unsigned char g_orc[BUF];
static unsigned char g_a[BUF];
static unsigned char g_b[BUF];

static int g_fail;
static unsigned g_checks;

static uint32_t g_rng = 0xC0FFEEu;

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

static void fail_msg(const char *name, const char *what, size_t n, size_t da, size_t sa)
{
    if (g_fail < 8)
        printf("FAIL %s %s n=%u dst_align=%u src_align=%u\n",
               name, what, (unsigned)n, (unsigned)da, (unsigned)sa);
    g_fail++;
}

static int sign_eq(int x, int y)
{
    return (x < 0) == (y < 0) && (x > 0) == (y > 0) && (x == 0) == (y == 0);
}

typedef void *(*copy_fn)(void *, const void *, size_t);
typedef void *(*set_fn)(void *, int, size_t);
typedef int (*cmp_fn)(const void *, const void *, size_t);

static void check_copy(const char *name, copy_fn fn, size_t n, size_t da, size_t sa)
{
    size_t i;
    void *ret;
    unsigned char *dst = g_dst + PAD + da;
    unsigned char *src = g_src + PAD + sa;
    unsigned char *orc = g_orc + PAD + da;

    if (PAD + da + n + 8 >= BUF || PAD + sa + n + 8 >= BUF) {
        fail_msg(name, "copy range", n, da, sa);
        return;
    }

    poison(g_dst, BUF);
    poison(g_src, BUF);
    poison(g_orc, BUF);
    for (i = 0; i < n; i++)
        src[i] = (unsigned char)(rnd() & 0xFFu);
    memcpy(orc, src, n);
    memcpy(g_a, src, n);
    ret = fn(dst, src, n);
    g_checks++;
    if (ret != dst)
        fail_msg(name, "memcpy ret", n, da, sa);
    if (n && memcmp(dst, orc, n) != 0)
        fail_msg(name, "memcpy data", n, da, sa);
    if (!canary_ok(g_dst, (size_t)(dst - g_dst), (size_t)(dst - g_dst) + n))
        fail_msg(name, "memcpy canary", n, da, sa);
    if (n && memcmp(src, g_a, n) != 0)
        fail_msg(name, "memcpy src", n, da, sa);
    if (!canary_ok(g_src, (size_t)(src - g_src), (size_t)(src - g_src) + n))
        fail_msg(name, "memcpy src canary", n, da, sa);
}

static void check_set(const char *name, set_fn fn, size_t n, size_t da, int c)
{
    size_t i;
    void *ret;
    unsigned char uc;
    unsigned char *dst = g_dst + PAD + da;
    int bytes_ok = 1;

    if (PAD + da + n + 8 >= BUF) {
        fail_msg(name, "set range", n, da, 0);
        return;
    }
    poison(g_dst, BUF);
    uc = (unsigned char)c;
    ret = fn(dst, c, n);
    g_checks++;
    if (ret != dst)
        fail_msg(name, "memset ret", n, da, 0);
    for (i = 0; i < n; i++) {
        if (dst[i] != uc)
            bytes_ok = 0;
    }
    if (!bytes_ok)
        fail_msg(name, "memset data", n, da, (size_t)(uc));
    if (!canary_ok(g_dst, (size_t)(dst - g_dst), (size_t)(dst - g_dst) + n))
        fail_msg(name, "memset canary", n, da, 0);
}

static void check_cmp(const char *name, cmp_fn fn, size_t n, size_t da, size_t sa, int diff_at)
{
    size_t i;
    int got, exp;
    unsigned char *a = g_a + PAD + da;
    unsigned char *b = g_b + PAD + sa;

    if (PAD + da + n + 8 >= BUF || PAD + sa + n + 8 >= BUF) {
        fail_msg(name, "cmp range", n, da, sa);
        return;
    }
    poison(g_a, BUF);
    poison(g_b, BUF);
    for (i = 0; i < n; i++)
        a[i] = b[i] = (unsigned char)(0x30 + (i * 13u) % 200u);
    if (diff_at >= 0 && (size_t)diff_at < n)
        b[diff_at] ^= 0xFFu;
    memcpy(g_src, g_a, BUF);
    memcpy(g_dst, g_b, BUF);
    exp = memcmp(a, b, n);
    got = fn(a, b, n);
    g_checks++;
    if (!sign_eq(got, exp))
        fail_msg(name, "memcmp sign", n, da, sa);
    if (memcmp(g_a, g_src, BUF) != 0 || memcmp(g_b, g_dst, BUF) != 0)
        fail_msg(name, "memcmp clobber", n, da, sa);
}

/* First differing byte decides the sign. 0x80 > 0x7F. Magnitude stays free. */
static void check_order(const char *name, cmp_fn fn)
{
    static const unsigned char pairs[][2] = {
        { 0x00, 0x00 },
        { 0x00, 0x01 },
        { 0x01, 0x00 },
        { 0x7F, 0x80 },
        { 0x80, 0x7F },
        { 0xFF, 0x00 },
        { 0x00, 0xFF }
    };
    static const size_t lens[] = { 1, 2, 8, 15, 16, 17, 31, 32 };
    size_t pi, li, n, at, da;

    for (pi = 0; pi < sizeof pairs / sizeof pairs[0]; pi++) {
        for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
            n = lens[li];
            for (at = 0; at < n; at += (n > 4 ? n - 1 : 1)) {
                for (da = 0; da <= 7; da++) {
                    size_t i;
                    unsigned char *a = g_a + PAD + da;
                    unsigned char *b = g_b + PAD + da;
                    int got, exp;
                    if (PAD + da + n + 8 >= BUF) {
                        fail_msg(name, "order range", n, da, at);
                        continue;
                    }
                    poison(g_a, BUF);
                    poison(g_b, BUF);
                    for (i = 0; i < n; i++)
                        a[i] = b[i] = (unsigned char)(0x11 + i);
                    a[at] = pairs[pi][0];
                    b[at] = pairs[pi][1];
                    memcpy(g_src, g_a, BUF);
                    memcpy(g_dst, g_b, BUF);
                    exp = memcmp(a, b, n);
                    got = fn(a, b, n);
                    g_checks++;
                    if (!sign_eq(got, exp))
                        fail_msg(name, "memcmp order", n, da, at);
                    if (memcmp(g_a, g_src, BUF) != 0 || memcmp(g_b, g_dst, BUF) != 0)
                        fail_msg(name, "memcmp clobber", n, da, at);
                }
            }
        }
    }
}

static void check_move(const char *name, copy_fn fn, size_t n, size_t off, int dst_above)
{
    size_t span = n + off;
    size_t i;
    unsigned char *win, *src, *dst;
    void *ret;

    if (PAD + span + 8 >= BUF) {
        fail_msg(name, "memmove range", n, off, (size_t)dst_above);
        return;
    }
    win = g_dst + PAD;
    poison(g_dst, BUF);
    poison(g_orc, BUF);
    for (i = 0; i < span; i++)
        win[i] = (unsigned char)(0x40 + (unsigned)((i * 3u) & 0xFFu));
    memcpy(g_orc, g_dst, BUF);
    if (dst_above) {
        dst = win + off;
        src = win;
    } else {
        dst = win;
        src = win + off;
    }
    memmove(g_orc + (dst - g_dst), g_orc + (src - g_dst), n);
    ret = fn(dst, src, n);
    g_checks++;
    if (ret != dst)
        fail_msg(name, "memmove ret", n, off, (size_t)dst_above);
    if (memcmp(g_dst, g_orc, BUF) != 0)
        fail_msg(name, "memmove data", n, off, (size_t)dst_above);
}

/* Non-overlapping both orders. Same object, so the backward loop is forced
   when dst > src. Caller must pass a span that fits. */
static void check_move_gap(const char *name, copy_fn fn, size_t n, size_t gap, int dst_low)
{
    size_t span;
    size_t i;
    unsigned char *win, *src, *dst;
    void *ret;

    if (gap == 0 || n > (BUF / 2) || PAD + n + gap + n + 8 >= BUF) {
        fail_msg(name, "memmove gap", n, gap, (size_t)dst_low);
        return;
    }
    span = n + gap + n;
    win = g_dst + PAD;
    poison(g_dst, BUF);
    poison(g_orc, BUF);
    for (i = 0; i < span; i++)
        win[i] = (unsigned char)(0x20 + (unsigned)(i & 0xFFu));
    memcpy(g_orc, g_dst, BUF);
    if (dst_low) {
        dst = win;
        src = win + n + gap;
    } else {
        src = win;
        dst = win + n + gap;
    }
    memmove(g_orc + (dst - g_dst), g_orc + (src - g_dst), n);
    ret = fn(dst, src, n);
    g_checks++;
    if (ret != dst)
        fail_msg(name, "memmove ret", n, gap, (size_t)dst_low);
    if (memcmp(g_dst, g_orc, BUF) != 0)
        fail_msg(name, "memmove data", n, gap, (size_t)dst_low);
}

static void exercise(const char *name, copy_fn cpy, set_fn set, cmp_fn cmp)
{
    static const size_t lens[] = {
        0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33,
        63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512,
        1000, 4096
    };
    static const int fills[] = { 0, 1, 0x7F, 0x80, 0xFF, -1, 256 + 65 };
    size_t li, da, sa;
    int fi, diff;

    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        for (da = 0; da <= 64; da += (lens[li] < 128 ? 1 : 17)) {
            for (sa = 0; sa <= 32; sa += (lens[li] < 64 ? 3 : 16))
                check_copy(name, cpy, lens[li], da, sa);
            for (fi = 0; fi < (int)(sizeof fills / sizeof fills[0]); fi++)
                check_set(name, set, lens[li], da, fills[fi]);
            check_cmp(name, cmp, lens[li], da, 0, -1);
            if (lens[li]) {
                check_cmp(name, cmp, lens[li], da, da & 7, 0);
                check_cmp(name, cmp, lens[li], da, 1, (int)(lens[li] - 1));
                check_cmp(name, cmp, lens[li], da, 3, (int)(lens[li] / 2));
            }
        }
    }
    for (diff = 0; diff < 48; diff++)
        check_cmp(name, cmp, 48, diff & 15, 2, diff);
    check_order(name, cmp);
}

static void exercise_move(const char *name, copy_fn fn)
{
    static const size_t lens[] = {
        0, 1, 2, 3, 4, 7, 8, 15, 16, 17, 31, 32, 33,
        63, 64, 65, 127, 128, 255, 256, 257, 1000, 4096
    };
    static const size_t offs[] = { 0, 1, 2, 3, 7, 8, 15, 16, 31, 32 };
    static const size_t gaps[] = { 1, 8, 16 };
    size_t li, oi, gi;

    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        for (oi = 0; oi < sizeof offs / sizeof offs[0]; oi++) {
            check_move(name, fn, lens[li], offs[oi], 1);
            if (offs[oi])
                check_move(name, fn, lens[li], offs[oi], 0);
        }
        for (gi = 0; gi < sizeof gaps / sizeof gaps[0]; gi++) {
            /* Two copies of a 4096-byte block do not fit. Overlap above still runs. */
            if (lens[li] > (BUF / 2) || PAD + lens[li] + gaps[gi] + lens[li] + 8 >= BUF)
                continue;
            check_move_gap(name, fn, lens[li], gaps[gi], 1);
            check_move_gap(name, fn, lens[li], gaps[gi], 0);
        }
    }
}

#if defined(__i386__) && !defined(__x86_64__)
static int have_mmx(void)
{
    unsigned eax, ebx, ecx, edx;
    unsigned max;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(0));
    max = eax;
    if (max < 1)
        return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1));
    return (edx & (1u << 23)) != 0;
}

static int have_sse(void)
{
    unsigned eax, ebx, ecx, edx;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(0));
    if (eax < 1)
        return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1));
    return (edx & (1u << 25)) != 0;
}
#elif defined(__x86_64__)
static unsigned long long xcr0(void)
{
    unsigned eax, edx;
    __asm__ volatile("xgetbv" : "=a"(eax), "=d"(edx) : "c"(0));
    return ((unsigned long long)edx << 32) | eax;
}

static int have_avx2(void)
{
    unsigned eax, ebx, ecx, edx, max, max7;
    __asm__ volatile("cpuid" : "=a"(max), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(0));
    if (max < 1)
        return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1));
    if ((ecx & (1u << 27)) == 0 || (ecx & (1u << 28)) == 0)
        return 0;
    if ((xcr0() & 0x6ull) != 0x6ull)
        return 0;
    __asm__ volatile("cpuid" : "=a"(max7), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(7), "c"(0));
    (void)max7;
    return (ebx & (1u << 5)) != 0;
}

static int have_avx512(void)
{
    unsigned eax, ebx, ecx, edx;
    if (!have_avx2())
        return 0;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(7), "c"(0));
    if ((ebx & (1u << 16)) == 0 || (ebx & (1u << 30)) == 0)
        return 0;
    return (xcr0() & 0xE6ull) == 0xE6ull;
}
#endif

int main(void)
{
    exercise_move("scalar", rt_memmove_scalar);
#if defined(__i386__) && !defined(__x86_64__)
    exercise("scalar", rt_memcpy_scalar, rt_memset_scalar, rt_memcmp_scalar);
    exercise("i386", rt_memcpy_i386, rt_memset_i386, rt_memcmp_i386);
    exercise("pc98", rt_memcpy_pc98, rt_memset_pc98, rt_memcmp_pc98);
    exercise("pc98-vram", rt_memcpy_pc98_vram, rt_memset_pc98_vram, rt_memcmp_pc98);
    if (have_mmx())
        exercise("mmx", rt_memcpy_mmx, rt_memset_mmx, rt_memcmp_mmx);
    else
        printf("skip mmx\n");
    if (have_sse())
        exercise("sse", rt_memcpy_sse, rt_memset_sse, rt_memcmp_sse);
    else
        printf("skip sse\n");
#elif defined(__x86_64__)
    exercise("scalar", rt_memcpy_scalar, rt_memset_scalar, rt_memcmp_scalar);
    exercise("sse2", rt_memcpy_sse2, rt_memset_sse2, rt_memcmp_sse2);
    if (have_avx2())
        exercise("avx2", rt_memcpy_avx2, rt_memset_avx2, rt_memcmp_avx2);
    else
        printf("skip avx2\n");
    if (have_avx512())
        exercise("avx512", rt_memcpy_avx512, rt_memset_avx512, rt_memcmp_avx512);
    else
        printf("skip avx512\n");
#elif defined(__aarch64__) || defined(__arm64__)
    exercise("scalar", rt_memcpy_scalar, rt_memset_scalar, rt_memcmp_scalar);
    exercise("neon", rt_memcpy_neon, rt_memset_neon, rt_memcmp_neon);
#else
#error rt verify: unsupported architecture
#endif
    if (g_fail) {
        printf("%d failures, %u checks\n", g_fail, g_checks);
        return 1;
    }
    printf("ok %u checks\n", g_checks);
    return 0;
}
