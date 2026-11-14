/* Freestanding contract bench for one AArch32 kernel.
   Compile with -DRT_SUF=m0 (or m3, m4, m7, m33, m55, arm1176, a32).
   No libc. The cycle counter on these QEMU machines does not advance,
   so this program prints no nanoseconds. */
#include <stddef.h>

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
    checks++;
    if (cond)
        return;
    fails++;
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
static unsigned char page[4096 + 64] __attribute__((aligned(4096), section(".bss.page")));

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

int main(void)
{
#ifdef RT_CPACR
    enable_mve();
#endif
    sh_write0("aarch32 " STR(RT_SUF) "\n");
    sh_write0("libc ns N/A\n");
    sh_write0("rt ns N/A\n");
    test_mem();
    test_strings();
    test_page();
    sh_write0("TOTAL checks ");
    put_u(checks);
    sh_write0(" fail ");
    put_u(fails);
    sh_write0("\n");
    sh_exit(fails ? 1 : 0);
    for (;;)
        ;
}
