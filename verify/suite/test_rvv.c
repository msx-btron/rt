/* Contract checker for the RVV memory and string kernels.
   No libc. QEMU virt runs it; a fault at the end of the 4MB RAM is a
   failed over-read. Guest time is not a result. */
#include "rt/mem.h"
#include "rt/string.h"

#include <stddef.h>
#include <stdint.h>

extern void uart_putc(int c);
extern void uart_flush(void);

enum { MEM = 400, STR = 512, RAM_END = 0x80400000u };

static unsigned char g_a[MEM];
static unsigned char g_b[MEM];
static unsigned char g_c[MEM];
static char g_s[STR];
static char g_d[STR];
static char g_e[STR];

static unsigned checks;
static unsigned first_fail;

static void put_s(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

static void put_u(unsigned n)
{
    char b[10];
    int i;

    if (n == 0) {
        uart_putc('0');
        return;
    }
    i = 0;
    while (n) {
        b[i++] = (char)('0' + (n % 10u));
        n /= 10u;
    }
    while (i)
        uart_putc(b[--i]);
}

static void note(const char *s)
{
    put_s(s);
    uart_putc('\n');
    uart_flush();
}

static void expect(int ok, unsigned id)
{
    checks++;
    if (!ok && first_fail == 0) {
        first_fail = id;
        put_s("fail ");
        put_u(id);
        uart_putc('\n');
        uart_flush();
    }
}

static int sgn(int x)
{
    return (x > 0) - (x < 0);
}

static void poison(unsigned char *p, unsigned n, unsigned char v)
{
    unsigned i;
    for (i = 0; i < n; i++)
        p[i] = v;
}

static int bytes_eq(const void *a, const void *b, unsigned n)
{
    const unsigned char *x = a;
    const unsigned char *y = b;
    unsigned i;
    for (i = 0; i < n; i++) {
        if (x[i] != y[i])
            return 0;
    }
    return 1;
}

static int tail_is(const unsigned char *p, unsigned begin, unsigned end, unsigned char v)
{
    unsigned i;
    for (i = begin; i < end; i++) {
        if (p[i] != v)
            return 0;
    }
    return 1;
}

static unsigned char *ram_end(void)
{
    return (unsigned char *)(uintptr_t)RAM_END;
}

static void poke(unsigned char *p, unsigned char v)
{
    *(volatile unsigned char *)p = v;
}

static unsigned char peek(const unsigned char *p)
{
    return *(const volatile unsigned char *)p;
}

static unsigned ref_strlen(const char *s)
{
    unsigned n = 0;
    while (s[n] != '\0')
        n++;
    return n;
}

static unsigned ref_strnlen(const char *s, unsigned n)
{
    unsigned i = 0;
    while (i < n && s[i] != '\0')
        i++;
    return i;
}

static int ref_strcmp(const char *a, const char *b)
{
    while (*a && (unsigned char)*a == (unsigned char)*b) {
        a++;
        b++;
    }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

static int ref_strncmp(const char *a, const char *b, unsigned n)
{
    unsigned i = 0;
    if (n == 0)
        return 0;
    while (i < n && a[i] && (unsigned char)a[i] == (unsigned char)b[i])
        i++;
    if (i == n)
        return 0;
    return (int)(unsigned char)a[i] - (int)(unsigned char)b[i];
}

static char *ref_strchr(const char *s, int c)
{
    unsigned char uc = (unsigned char)c;
    while (*s) {
        if ((unsigned char)*s == uc)
            return (char *)s;
        s++;
    }
    if (uc == 0)
        return (char *)s;
    return 0;
}

static char *ref_strrchr(const char *s, int c)
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

static char *ref_strstr(const char *h, const char *n)
{
    unsigned nlen;
    unsigned i;
    if (n[0] == '\0')
        return (char *)h;
    nlen = ref_strlen(n);
    for (; *h; h++) {
        for (i = 0; i < nlen; i++) {
            if ((unsigned char)h[i] != (unsigned char)n[i])
                break;
        }
        if (i == nlen)
            return (char *)h;
    }
    return 0;
}

static char *ref_strpbrk(const char *s, const char *accept)
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

static unsigned ref_strscpy(char *dst, const char *src, unsigned n)
{
    unsigned i = 0;
    if (n == 0)
        return ref_strlen(src);
    while (i + 1 < n && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
    while (src[i] != '\0')
        i++;
    return i;
}

static unsigned ref_strscat(char *dst, const char *src, unsigned n)
{
    unsigned used = ref_strnlen(dst, n);
    if (used >= n)
        return used + ref_strlen(src);
    return used + ref_strscpy(dst + used, src, n - used);
}

static const unsigned lens[] = {
    0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31, 32, 33,
    63, 64, 65, 127, 128, 129, 255, 256
};
static const unsigned offs[] = { 0, 1, 2, 3, 7, 8, 15 };

static void test_mem(void)
{
    unsigned li, od, os, i, n, at;

    note("mem");
    for (li = 0; li < sizeof lens / sizeof lens[0]; li++) {
        n = lens[li];
        for (od = 0; od < sizeof offs / sizeof offs[0]; od++) {
            for (os = 0; os < sizeof offs / sizeof offs[0]; os++) {
                unsigned d = offs[od];
                unsigned s = offs[os];
                if (d + n + 8 > MEM || s + n + 8 > MEM)
                    continue;
                for (i = 0; i < n; i++)
                    g_b[s + i] = (unsigned char)(i * 3u + s + 1u);
                poison(g_a, MEM, 0xCC);
                expect(rt_memcpy_rvv(g_a + d, g_b + s, n) == g_a + d, 100 + n);
                expect(bytes_eq(g_a + d, g_b + s, n), 110 + n);
                expect(tail_is(g_a, 0, d, 0xCC), 120);
                expect(tail_is(g_a, d + n, MEM, 0xCC), 121);

                poison(g_a, MEM, 0xCC);
                expect(rt_memset_rvv(g_a + d, 0x1A5, n) == g_a + d, 200 + n);
                for (i = 0; i < n; i++)
                    expect(g_a[d + i] == 0xA5, 210);
                expect(tail_is(g_a, 0, d, 0xCC), 220);
                expect(tail_is(g_a, d + n, MEM, 0xCC), 221);

                poison(g_c, MEM, 0x11);
                for (i = 0; i < n; i++)
                    g_c[s + i] = g_b[s + i];
                expect(rt_memcmp_rvv(g_b + s, g_c + s, n) == 0, 300 + n);
            }
        }
    }

    poison(g_a, MEM, 0xCC);
    expect(rt_memset_rvv(g_a + 4, -1, 8) == g_a + 4, 230);
    for (i = 4; i < 12; i++)
        expect(g_a[i] == 0xFF, 231);
    expect(g_a[3] == 0xCC && g_a[12] == 0xCC, 232);
    expect(rt_memcpy_rvv(g_a, g_b, 0) == g_a, 140);
    expect(g_a[0] == 0xCC, 141);
    expect(rt_memset_rvv(g_a, 0x7E, 0) == g_a, 240);
    expect(g_a[0] == 0xCC, 241);
    expect(rt_memcmp_rvv(g_a, g_b, 0) == 0, 340);

    for (n = 1; n <= 64; n++) {
        for (at = 0; at < n; at++) {
            poison(g_a, 80, 0x20);
            poison(g_b, 80, 0x20);
            g_a[at] = 0xFF;
            g_b[at] = 0x01;
            expect(sgn(rt_memcmp_rvv(g_a, g_b, n)) > 0, 350);
            expect(sgn(rt_memcmp_rvv(g_b, g_a, n)) < 0, 351);
            g_a[at] = 0x80;
            g_b[at] = 0x7F;
            expect(sgn(rt_memcmp_rvv(g_a, g_b, n)) > 0, 352);
        }
    }
}

static void put_pat(char *p, unsigned n, unsigned al)
{
    unsigned i;
    for (i = 0; i < al + n + 32; i++)
        p[i] = (char)(0x41 + (i & 15));
    if (n)
        p[al + n - 1] = (char)0xFF;
    p[al + n] = '\0';
}

static void test_strlen_cmp(void)
{
    unsigned n, al;
    char a[160];
    char b[160];

    note("strlen");
    expect(rt_strlen_rvv("") == 0, 400);
    for (n = 0; n <= 80; n++) {
        for (al = 0; al <= 31; al++) {
            put_pat(g_s, n, al);
            expect(rt_strlen_rvv(g_s + al) == n, 410 + (n & 63));
        }
    }
    expect(rt_strnlen_rvv("abcdefghijklmnop", 0) == 0, 1500);
    expect(rt_strnlen_rvv("abcdefghijklmnop", 8) == 8, 1501);
    expect(rt_strnlen_rvv("hi", 10) == 2, 1502);
    expect(rt_strnlen_rvv("", 5) == 0, 1503);
    {
        char hi[4];
        hi[0] = 'a';
        hi[1] = (char)0xFF;
        hi[2] = 'b';
        hi[3] = 0;
        expect(rt_strnlen_rvv(hi, 10) == 3, 1504);
        expect(rt_strnlen_rvv(hi, 1) == 1, 1505);
    }

    note("strcmp");
    expect(rt_strcmp_rvv("", "") == 0, 600);
    expect(sgn(rt_strcmp_rvv("abc", "abcd")) == sgn(ref_strcmp("abc", "abcd")), 601);
    expect(sgn(rt_strcmp_rvv("abcd", "abc")) == sgn(ref_strcmp("abcd", "abc")), 602);
    expect(sgn(rt_strcmp_rvv("b", "a")) == sgn(ref_strcmp("b", "a")), 603);
    {
        char h1[2], h2[2];
        h1[0] = (char)0x80;
        h1[1] = 0;
        h2[0] = (char)0x7F;
        h2[1] = 0;
        expect(sgn(rt_strcmp_rvv(h1, h2)) > 0, 604);
        expect(sgn(rt_strcmp_rvv(h2, h1)) < 0, 605);
        h1[0] = (char)0xFF;
        h2[0] = 1;
        expect(sgn(rt_strcmp_rvv(h1, h2)) > 0, 606);
        expect(sgn(rt_strcmp_rvv(h2, h1)) < 0, 607);
    }
    for (n = 0; n <= 96; n++) {
        for (al = 0; al <= 15; al++) {
            unsigned i;
            for (i = 0; i < n; i++)
                a[al + i] = b[al + i] = (char)('a' + (i % 26));
            a[al + n] = b[al + n] = 0;
            expect(rt_strcmp_rvv(a + al, b + al) == 0, 610);
            if (n) {
                b[al + n - 1] = 'z';
                expect(sgn(rt_strcmp_rvv(a + al, b + al)) ==
                       sgn(ref_strcmp(a + al, b + al)), 611);
                expect(sgn(rt_strcmp_rvv(b + al, a + al)) ==
                       sgn(ref_strcmp(b + al, a + al)), 612);
            }
        }
    }
    expect(rt_strncmp_rvv("abc", "xyz", 0) == 0, 1100);
    expect(rt_strncmp_rvv("abc", "abd", 2) == 0, 1101);
    expect(sgn(rt_strncmp_rvv("abc", "abd", 3)) == sgn(ref_strncmp("abc", "abd", 3)), 1102);
    expect(rt_strncmp_rvv("ab", "abcd", 4) == ref_strncmp("ab", "abcd", 4) ||
           sgn(rt_strncmp_rvv("ab", "abcd", 4)) == sgn(ref_strncmp("ab", "abcd", 4)), 1103);
    expect(sgn(rt_strncmp_rvv("ab", "abcd", 4)) < 0, 1104);
    {
        char h1[2], h2[2];
        h1[0] = (char)0xFF;
        h1[1] = 0;
        h2[0] = 1;
        h2[1] = 0;
        expect(sgn(rt_strncmp_rvv(h1, h2, 1)) > 0, 1105);
    }
}

static void test_copy_find(void)
{
    unsigned n, i;
    static const unsigned try_n[] = { 0, 1, 2, 3, 7, 8, 15, 16, 17, 31, 32, 33, 64, 65 };

    note("strcpy");
    for (i = 0; i < sizeof try_n / sizeof try_n[0]; i++) {
        unsigned len = try_n[i];
        char raw[96];
        poison((unsigned char *)g_d, 96, 0xA5);
        poison((unsigned char *)g_e, 96, 0xA5);
        for (n = 0; n < len; n++)
            raw[n] = (n + 1 == len) ? (char)0xFF : (char)('A' + (n % 26));
        raw[len] = 0;
        expect(rt_strcpy_rvv(g_d, raw) == g_d, 500 + len);
        expect(bytes_eq(g_d, raw, len + 1), 510);
        expect(tail_is((unsigned char *)g_d, len + 1, 96, 0xA5), 511);
        poison((unsigned char *)g_d, 96, 0xA5);
        expect(rt_strncpy_rvv(g_d, raw, len + 3) == g_d, 800 + len);
        expect(bytes_eq(g_d, raw, len + 1), 810);
        expect(tail_is((unsigned char *)g_d, len + 1, len + 3, 0), 811);
        expect(((unsigned char *)g_d)[len + 3] == 0xA5, 812);
        if (len >= 3) {
            poison((unsigned char *)g_d, 16, 0xA5);
            expect(rt_strncpy_rvv(g_d, raw, 3) == g_d, 820);
            expect(bytes_eq(g_d, raw, 3), 821);
            expect(((unsigned char *)g_d)[3] == 0xA5, 822);
        }
    }
    poison((unsigned char *)g_d, 8, 0xA5);
    expect(rt_strncpy_rvv(g_d, "hi", 0) == g_d, 830);
    expect(((unsigned char *)g_d)[0] == 0xA5, 831);

    poison((unsigned char *)g_d, 16, 0xCC);
    g_d[0] = 'a';
    g_d[1] = 'b';
    g_d[2] = 0;
    expect(rt_strcat_rvv(g_d, "cd") == g_d, 900);
    expect(bytes_eq(g_d, "abcd", 5), 901);
    expect(((unsigned char *)g_d)[5] == 0xCC, 902);
    g_d[0] = 0;
    expect(rt_strcat_rvv(g_d, "") == g_d && g_d[0] == 0, 903);
    g_d[0] = 'z';
    g_d[1] = 0;
    g_d[2] = (char)0xCC;
    expect(rt_strncat_rvv(g_d, "xy", 0) == g_d, 1000);
    expect(g_d[0] == 'z' && g_d[1] == 0 && (unsigned char)g_d[2] == 0xCC, 1001);
    expect(rt_strncat_rvv(g_d, "xyz", 1) == g_d, 1002);
    expect(bytes_eq(g_d, "zx", 3), 1003);

    note("strchr");
    expect(rt_strchr_rvv("", 'a') == 0, 700);
    expect(rt_strchr_rvv("x", 'x') == ref_strchr("x", 'x'), 701);
    expect(rt_strchr_rvv("x", 0) == ref_strchr("x", 0), 702);
    expect(rt_strchr_rvv("abca", 'a') == ref_strchr("abca", 'a'), 703);
    expect(rt_strchr_rvv("abca", 'z') == 0, 704);
    expect(rt_strchr_rvv("abca", 256 + 'a') == ref_strchr("abca", 256 + 'a'), 705);
    expect(rt_strchr_rvv("abca", 256) == ref_strchr("abca", 256), 706);
    {
        char hi[8];
        hi[0] = 'a';
        hi[1] = (char)0xFF;
        hi[2] = 'b';
        hi[3] = 0;
        expect(rt_strchr_rvv(hi, 0xFF) == hi + 1, 707);
        expect(rt_strchr_rvv(hi, 256 + 0xFF) == hi + 1, 708);
    }
    expect(rt_strrchr_rvv("abca", 'a') == ref_strrchr("abca", 'a'), 1200);
    expect(rt_strrchr_rvv("abca", 'z') == 0, 1201);
    expect(rt_strrchr_rvv("abca", 0) == ref_strrchr("abca", 0), 1202);
    expect(rt_strrchr_rvv("", 'a') == 0, 1203);
    expect(rt_strrchr_rvv("", 0) == ref_strrchr("", 0), 1204);
    {
        char hi[8];
        hi[0] = (char)0xFF;
        hi[1] = 'a';
        hi[2] = (char)0xFF;
        hi[3] = 0;
        expect(rt_strrchr_rvv(hi, 0xFF) == hi + 2, 1205);
    }

    note("strstr");
    expect(rt_strstr_rvv("hay", "") == ref_strstr("hay", ""), 1300);
    expect(rt_strstr_rvv("", "") == ref_strstr("", ""), 1301);
    expect(rt_strstr_rvv("", "a") == 0, 1302);
    expect(rt_strstr_rvv("needle-at-start", "needle") == ref_strstr("needle-at-start", "needle"), 1303);
    expect(rt_strstr_rvv("xxneedle", "needle") == ref_strstr("xxneedle", "needle"), 1304);
    expect(rt_strstr_rvv("aaaab", "aaab") == ref_strstr("aaaab", "aaab"), 1305);
    expect(rt_strstr_rvv("ababcabcd", "abc") == ref_strstr("ababcabcd", "abc"), 1306);
    expect(rt_strstr_rvv("abc", "abcd") == 0, 1307);
    expect(rt_strstr_rvv("abc", "nope") == 0, 1308);
    {
        char hi[8];
        hi[0] = 'a';
        hi[1] = (char)0xFF;
        hi[2] = 'b';
        hi[3] = 0;
        expect(rt_strstr_rvv(hi, "\377b") == hi + 1, 1309);
    }
    expect(rt_strpbrk_rvv("abc", "") == 0, 1400);
    expect(rt_strpbrk_rvv("abc", "xby") == ref_strpbrk("abc", "xby"), 1401);
    expect(rt_strpbrk_rvv("abc", "xyz") == 0, 1402);
    expect(rt_strpbrk_rvv("", "a") == 0, 1403);
    {
        char hi[4];
        hi[0] = 'a';
        hi[1] = (char)0xFF;
        hi[2] = 0;
        expect(rt_strpbrk_rvv(hi, "\377") == hi + 1, 1404);
    }
}

static void test_bounded(void)
{
    unsigned n;
    const char *src = "abcdefghij";
    unsigned srclen = ref_strlen(src);

    note("bounded");
    for (n = 0; n <= 16; n++) {
        char dst[32];
        char exp[32];
        unsigned got, eg;
        poison((unsigned char *)dst, 32, 0xCC);
        poison((unsigned char *)exp, 32, 0xCC);
        got = rt_strscpy_rvv(dst, src, n);
        eg = ref_strscpy(exp, src, n);
        expect(got == srclen && got == eg, 1600 + n);
        expect(bytes_eq(dst, exp, 32), 1620 + n);
    }
    {
        char src2[4];
        char dst[8];
        src2[0] = 'Q';
        src2[1] = (char)0xFF;
        src2[2] = 'Z';
        src2[3] = 0;
        poison((unsigned char *)dst, 8, 0xCC);
        expect(rt_strscpy_rvv(dst, src2, 8) == 3, 1640);
        expect(dst[0] == 'Q' && (unsigned char)dst[1] == 0xFF &&
               dst[2] == 'Z' && dst[3] == 0 && (unsigned char)dst[4] == 0xCC, 1641);
        poison((unsigned char *)dst, 8, 0xCC);
        expect(rt_strscpy_rvv(dst, src2, 1) == 3, 1642);
        expect(dst[0] == 0 && (unsigned char)dst[1] == 0xCC, 1643);
    }

    {
        char dst[16];
        char exp[16];
        poison((unsigned char *)dst, 16, 0xCC);
        poison((unsigned char *)exp, 16, 0xCC);
        dst[0] = exp[0] = 'a';
        dst[1] = exp[1] = 'b';
        dst[2] = exp[2] = 0;
        expect(rt_strscat_rvv(dst, "cd", 8) == ref_strscat(exp, "cd", 8), 1700);
        expect(bytes_eq(dst, exp, 16), 1701);
        poison((unsigned char *)dst, 8, 'a');
        poison((unsigned char *)exp, 8, 'a');
        expect(rt_strscat_rvv(dst, "z", 4) == 5, 1702);
        expect(bytes_eq(dst, exp, 8), 1703);
        dst[0] = 0;
        expect(rt_strscat_rvv(dst, "hi", 0) == 2, 1704);
        expect(dst[0] == 0, 1705);
    }

    poison((unsigned char *)g_d, 16, 0xCC);
    rt_strpad_rvv(g_d, "ab", 5, 'x');
    expect(bytes_eq(g_d, "abxxx", 5), 1800);
    expect(((unsigned char *)g_d)[5] == 0xCC, 1801);
    poison((unsigned char *)g_d, 16, 0xCC);
    rt_strpad_rvv(g_d, "abcdef", 3, 'x');
    expect(bytes_eq(g_d, "abc", 3), 1802);
    expect(((unsigned char *)g_d)[3] == 0xCC, 1803);
    poison((unsigned char *)g_d, 8, 0xCC);
    rt_strpad_rvv(g_d, "ab", 0, 'x');
    expect(((unsigned char *)g_d)[0] == 0xCC, 1804);
    poison((unsigned char *)g_d, 8, 0xCC);
    rt_strpad_rvv(g_d, "", 3, 0x1FF);
    expect((unsigned char)g_d[0] == 0xFF && (unsigned char)g_d[1] == 0xFF &&
           (unsigned char)g_d[2] == 0xFF && (unsigned char)g_d[3] == 0xCC, 1805);
}

static void test_edge(void)
{
    unsigned char *end = ram_end();
    unsigned char *p;
    unsigned i;
    char dst[32];

    note("edge");
    p = end - 1;
    poke(p, 0);
    expect(rt_strlen_rvv((char *)p) == 0, 1900);
    expect(rt_strchr_rvv((char *)p, 0) == (char *)p, 1901);
    expect(rt_strchr_rvv((char *)p, 'a') == 0, 1902);
    expect(rt_strcmp_rvv((char *)p, "") == 0, 1903);
    expect(rt_strncmp_rvv((char *)end, (char *)end, 0) == 0, 1904);
    expect(rt_memcmp_rvv(end, end, 0) == 0, 1905);

    p = end - 2;
    poke(p, 'Z');
    poke(p + 1, 0);
    expect(rt_strlen_rvv((char *)p) == 1, 1910);
    expect(rt_strcpy_rvv(dst, (char *)p) == dst && dst[0] == 'Z' && dst[1] == 0, 1911);
    expect(rt_strcmp_rvv((char *)p, "Z") == 0, 1912);
    expect(rt_strchr_rvv((char *)p, 'Z') == (char *)p, 1913);
    expect(rt_strstr_rvv((char *)p, "abc") == 0, 1914);
    expect(rt_strscpy_rvv(dst, (char *)p, 0) == 1 && (unsigned char)dst[0] == 'Z', 1915);

    p = end - 80;
    for (i = 0; i < 80; i++)
        poke(p + i, (unsigned char)(0x40 + (i & 15)));
    poison(g_a, 80, 0);
    expect(rt_memcpy_rvv(g_a, p, 80) == g_a, 1920);
    expect(bytes_eq(g_a, p, 80), 1921);
    expect(rt_memcmp_rvv(g_a, p, 80) == 0, 1922);
    expect(rt_memset_rvv(p, 0x5A, 80) == p, 1923);
    for (i = 0; i < 80; i++)
        expect(peek(p + i) == 0x5A, 1924);

    p = end - 5;
    poke(p, 'a');
    poke(p + 1, 'b');
    poke(p + 2, 'c');
    poke(p + 3, 'd');
    poke(p + 4, 0);
    expect(rt_strlen_rvv((char *)p) == 4, 1930);
    expect(rt_strstr_rvv((char *)p, "bcd") == (char *)(p + 1), 1931);
    expect(rt_strrchr_rvv((char *)p, 'b') == (char *)(p + 1), 1932);
}

int rvv_main(void)
{
    note("rvv start");
    test_mem();
    test_strlen_cmp();
    test_copy_find();
    test_bounded();
    test_edge();
    if (first_fail) {
        put_s("rvv FAIL ");
        put_u(first_fail);
        put_s(" checks ");
        put_u(checks);
        uart_putc('\n');
        uart_flush();
        return (int)first_fail;
    }
    put_s("rvv ok checks ");
    put_u(checks);
    uart_putc('\n');
    uart_flush();
    return 0;
}
