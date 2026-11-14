/* Freestanding MIPS bench. PCSX2 prints the SIO bytes for the
   Emotion Engine. RT_MALTA prints the Malta UART for the VR4300
   stand-in. The oracle is a byte loop in this file. RT_WITH_EE or
   RT_WITH_RCP also times that kernel beside the scalar objects. */
#include "rt/mem.h"
#include "rt/string.h"

#include <stddef.h>
#include <stdint.h>

#if defined(RT_WITH_EE) && defined(RT_WITH_RCP)
#error one wide kernel
#endif
#if defined(RT_WITH_EE) || defined(RT_WITH_RCP)
#define RT_WIDE 1
#endif
#if defined(RT_WITH_RCP)
#define RT_KIND "rcp"
#define rt_memcpy_ee rt_memcpy_rcp
#define rt_memset_ee rt_memset_rcp
#define rt_memcmp_ee rt_memcmp_rcp
#define rt_strlen_ee rt_strlen_rcp
#define rt_strnlen_ee rt_strnlen_rcp
#define rt_strcpy_ee rt_strcpy_rcp
#define rt_strncpy_ee rt_strncpy_rcp
#define rt_strcat_ee rt_strcat_rcp
#define rt_strncat_ee rt_strncat_rcp
#define rt_strcmp_ee rt_strcmp_rcp
#define rt_strncmp_ee rt_strncmp_rcp
#define rt_strchr_ee rt_strchr_rcp
#define rt_strrchr_ee rt_strrchr_rcp
#define rt_strstr_ee rt_strstr_rcp
#define rt_strpbrk_ee rt_strpbrk_rcp
#define rt_strscpy_ee rt_strscpy_rcp
#define rt_strscat_ee rt_strscat_rcp
#define rt_strpad_ee rt_strpad_rcp
#elif defined(RT_WITH_EE)
#define RT_KIND "ee"
#endif

void *rt_memcpy_ee(void *dst, const void *src, size_t n);
void *rt_memset_ee(void *dst, int c, size_t n);
int rt_memcmp_ee(const void *a, const void *b, size_t n);
size_t rt_strlen_ee(const char *s);
size_t rt_strnlen_ee(const char *s, size_t n);
char *rt_strcpy_ee(char *dst, const char *src);
char *rt_strncpy_ee(char *dst, const char *src, size_t n);
char *rt_strcat_ee(char *dst, const char *src);
char *rt_strncat_ee(char *dst, const char *src, size_t n);
int rt_strcmp_ee(const char *a, const char *b);
int rt_strncmp_ee(const char *a, const char *b, size_t n);
char *rt_strchr_ee(const char *s, int c);
char *rt_strrchr_ee(const char *s, int c);
char *rt_strstr_ee(const char *hay, const char *needle);
char *rt_strpbrk_ee(const char *s, const char *accept);
size_t rt_strscpy_ee(char *dst, const char *src, size_t n);
size_t rt_strscat_ee(char *dst, const char *src, size_t n);
void rt_strpad_ee(char *dst, const char *src, size_t width, int fill);

static unsigned g_fail;
static unsigned g_check;

#if defined(RT_MALTA)
/* QEMU Malta 16550. The 32-bit port is sign-extended into kseg1. */
static volatile uint8_t *const uart =
    (volatile uint8_t *)(uintptr_t)(intptr_t)(int32_t)0xb80003f8;

extern char __bss_start[];
extern char _end[];

static void clear_bss(void)
{
    char *p;

    for (p = __bss_start; p < _end; p++)
        *p = 0;
}

static void sio_init(void)
{
    uart[3] = 0x80;
    uart[0] = 1;
    uart[1] = 0;
    uart[3] = 3;
    uart[2] = 7;
    uart[1] = 0;
}

static void putc(char c)
{
    unsigned spin;

    if (c == '\n')
        putc('\r');
    spin = 0;
    while ((uart[5] & 0x20) == 0 && ++spin < 1000000u)
        ;
    uart[0] = (uint8_t)c;
}
#else
static void sio_init(void)
{
    volatile uint32_t *r = (volatile uint32_t *)0x1000F100u;
    r[0] = 32u;
    r[8] = 0u;
    r[16] = 7u;
    r[16] = 0u;
    r[20] = 9u;
}

static void putc(char c)
{
    volatile uint32_t *isr = (volatile uint32_t *)0x1000F130u;
    volatile uint8_t *tx = (volatile uint8_t *)0x1000F180u;
    unsigned spin;

    if (c == '\n')
        putc('\r');
    spin = 0;
    while ((*isr & 0xF000u) == 0x8000u && ++spin < 50000u)
        ;
    *tx = (uint8_t)c;
}
#endif

static void puts(const char *s)
{
    while (*s)
        putc(*s++);
}

static void putu(unsigned v)
{
    char b[16];
    int i = 0;
    if (v == 0) {
        putc('0');
        return;
    }
    while (v) {
        b[i++] = (char)('0' + (v % 10u));
        v /= 10u;
    }
    while (i)
        putc(b[--i]);
}

static unsigned ee_count(void)
{
    unsigned v;
    __asm__ volatile("mfc0 %0, $9" : "=r"(v));
    return v;
}

static void expect(int ok, const char *what)
{
    g_check++;
    if (!ok) {
        if (g_fail < 8u) {
            puts("FAIL ");
            puts(what);
            putc('\n');
        }
        g_fail++;
    }
}

static int o_memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;
    size_t i;
    for (i = 0; i < n; i++) {
        if (x[i] != y[i])
            return (int)x[i] - (int)y[i];
    }
    return 0;
}

static void o_memcpy(void *d, const void *s, size_t n)
{
    unsigned char *dd = (unsigned char *)d;
    const unsigned char *ss = (const unsigned char *)s;
    size_t i;
    for (i = 0; i < n; i++)
        dd[i] = ss[i];
}

static void o_memset(void *d, int c, size_t n)
{
    unsigned char *dd = (unsigned char *)d;
    size_t i;
    for (i = 0; i < n; i++)
        dd[i] = (unsigned char)c;
}

#if defined(RT_WIDE)
static size_t o_strlen(const char *s)
{
    size_t n = 0;
    while (s[n])
        n++;
    return n;
}
#endif

static void fill(unsigned char *p, size_t n, unsigned seed)
{
    size_t i;
    for (i = 0; i < n; i++)
        p[i] = (unsigned char)(seed + i * 17u);
}

static unsigned char srcb[2048] __attribute__((aligned(64)));
static unsigned char dsta[2048] __attribute__((aligned(64)));
static unsigned char dstb[2048] __attribute__((aligned(64)));
#if defined(RT_WIDE)
static unsigned char page[8192] __attribute__((aligned(4096)));
#endif

static void check_mem(void)
{
    size_t n, da, sa;
    puts("mem\n");
    for (n = 0; n <= 96; n++) {
        for (da = 0; da < 16; da++) {
            for (sa = 0; sa < 16; sa++) {
                fill(srcb, 160, 3);
                o_memset(dsta, 0x5A, 200);
                o_memset(dstb, 0x5A, 200);
                o_memcpy(dsta + da, srcb + sa, n);
#if defined(RT_WIDE)
                rt_memcpy_ee(dstb + da, srcb + sa, n);
                expect(o_memcmp(dsta, dstb, 200) == 0, "memcpy");
                o_memset(dstb, 0x5A, 200);
                rt_memset_ee(dstb + da, 0xA5, n);
                o_memset(dsta, 0x5A, 200);
                o_memset(dsta + da, 0xA5, n);
                expect(o_memcmp(dsta, dstb, 200) == 0, "memset");
                expect(rt_memcmp_ee(srcb + sa, srcb + sa, n) == 0, "memcmp0");
                if (n) {
                    srcb[sa + n - 1] ^= 0xFF;
                    expect(rt_memcmp_ee(srcb + sa, dsta + da, n) != 0 ||
                           n == 0, "memcmp-diff");
                    srcb[sa + n - 1] ^= 0xFF;
                }
#else
                (void)sa;
#endif
                rt_memcpy_scalar(dstb + da, srcb + sa, n);
                o_memset(dstb, 0x5A, 200);
                /* scalar result is checked against the oracle bytes */
                o_memcpy(dstb + da, srcb + sa, n);
                rt_memcpy_scalar(dsta + da, srcb + sa, n);
                expect(o_memcmp(dsta + da, dstb + da, n) == 0, "scalar-memcpy");
            }
        }
    }
    srcb[0] = 0xFF;
    srcb[1] = 1;
#if defined(RT_WIDE)
    expect(rt_memcmp_ee(srcb, srcb + 1, 1) > 0, "memcmp-hi");
    expect(rt_memcmp_ee(srcb + 1, srcb, 1) < 0, "memcmp-lo");
    expect(rt_memcmp_ee(srcb, srcb, 0) == 0, "memcmp-n0");
#endif
    expect(rt_memcmp_scalar(srcb, srcb + 1, 1) > 0, "scalar-hi");
}

static void plant(char *d, size_t n, int ch)
{
    size_t i;
    for (i = 0; i < n; i++)
        d[i] = (char)(ch < 0 ? ('A' + (int)(i % 26)) : ch);
    d[n] = 0;
}

static char sa[256] __attribute__((aligned(64)));
static char sb[256] __attribute__((aligned(64)));
#if defined(RT_WIDE)
static char sc[256] __attribute__((aligned(64)));
#endif

static void check_strings(void)
{
    static const size_t lens[] = { 0, 1, 2, 7, 8, 15, 16, 17, 31, 32, 63, 64 };
    size_t i, n, off;
    puts("str\n");
    for (i = 0; i < sizeof lens / sizeof lens[0]; i++) {
        n = lens[i];
        for (off = 0; off < 16; off++) {
            plant(sa + off, n, -1);
            if (n)
                sa[off + n - 1] = (char)0xFF;
#if defined(RT_WIDE)
            expect(rt_strlen_ee(sa + off) == n, "strlen");
            expect(rt_strnlen_ee(sa + off, n) == n, "strnlen");
            expect(rt_strnlen_ee(sa + off, n / 2) == n / 2, "strnlen-cap");
            o_memset(sb, 0xA5, sizeof sb);
            o_memset(sc, 0xA5, sizeof sc);
            rt_strcpy_ee(sb, sa + off);
            o_memcpy(sc, sa + off, n + 1);
            expect(o_memcmp(sb, sc, n + 1) == 0, "strcpy");
            expect(sb[n + 1] == (char)0xA5, "strcpy-tail");
            o_memset(sb, 0xA5, 80);
            rt_strncpy_ee(sb, sa + off, n + 3);
            expect(o_strlen(sb) == n, "strncpy");
            expect(sb[n + 1] == 0 && sb[n + 2] == 0, "strncpy-pad");
            expect(rt_strcmp_ee(sa + off, sa + off) == 0, "strcmp-eq");
            expect(rt_strncmp_ee(sa + off, sa + off, 0) == 0, "strncmp0");
            expect(rt_strchr_ee(sa + off, 0) == sa + off + n, "strchr0");
            expect(rt_strrchr_ee(sa + off, 0) == sa + off + n, "strrchr0");
#endif
            expect(rt_strlen(sa + off) == n, "scalar-strlen");
        }
    }
#if defined(RT_WIDE)
    plant(sa, 40, -1);
    sa[10] = 'Z';
    sa[30] = 'Z';
    expect(rt_strchr_ee(sa, 'Z') == sa + 10, "strchr");
    expect(rt_strrchr_ee(sa, 'Z') == sa + 30, "strrchr");
    expect(rt_strchr_ee(sa, 'q') == 0, "strchr-miss");
    expect(rt_strchr_ee(sa, 256 + 'Z') == sa + 10, "strchr-trunc");
    expect(rt_strstr_ee(sa, "") == sa, "strstr-empty");
    expect(rt_strstr_ee(sa, "Z") == sa + 10, "strstr");
    expect(rt_strstr_ee(sa, "nope") == 0, "strstr-miss");
    expect(rt_strstr_ee("", "a") == 0, "strstr-hay");
    expect(rt_strpbrk_ee(sa, "") == 0, "strpbrk-empty");
    expect(rt_strpbrk_ee(sa, "Z") == sa + 10, "strpbrk");
    expect(rt_strpbrk_ee(sa, "q") == 0, "strpbrk-miss");
    o_memset(sb, 0xA5, 32);
    o_memcpy(sb, "pre", 4);
    rt_strcat_ee(sb, "tail");
    expect(o_memcmp(sb, "pretail", 8) == 0, "strcat");
    o_memset(sb, 0xA5, 32);
    o_memcpy(sb, "pre", 4);
    rt_strncat_ee(sb, "tail", 2);
    expect(o_memcmp(sb, "preta", 6) == 0, "strncat");
    o_memset(sb, 0xA5, 32);
    o_memcpy(sb, "pre", 4);
    rt_strncat_ee(sb, "t", 0);
    expect(o_memcmp(sb, "pre", 4) == 0, "strncat0");
    plant(sa, 10, -1);
    expect(rt_strscpy_ee(sb, sa, 0) == 10, "strscpy0");
    o_memset(sb, 0xA5, 24);
    expect(rt_strscpy_ee(sb, sa, 4) == 10, "strscpy");
    expect(sb[0] == sa[0] && sb[2] == sa[2] && sb[3] == 0, "strscpy-nul");
    expect(sb[4] == (char)0xA5, "strscpy-past");
    o_memset(sb, 0xA5, 24);
    o_memcpy(sb, "pre", 4);
    expect(rt_strscat_ee(sb, sa, 8) == 3 + 10, "strscat");
    rt_strpad_ee(sc, sa, 4, 0x141);
    expect(o_memcmp(sc, sa, 4) == 0, "strpad-copy");
    rt_strpad_ee(sc, "ab", 4, 'x');
    expect(sc[0] == 'a' && sc[1] == 'b' && sc[2] == 'x' && sc[3] == 'x',
           "strpad-fill");
    sa[0] = (char)0xFF;
    sa[1] = 1;
    sa[2] = 0;
    sb[0] = 1;
    sb[1] = 1;
    sb[2] = 0;
    expect(rt_strcmp_ee(sa, sb) > 0, "strcmp-hi");
    expect(rt_strncmp_ee("ab", "abcd", 4) < 0, "strncmp-end");
    /* Page: 16-byte line at 4080, NUL twenty bytes later, next page mapped. */
    if (((uintptr_t)page & 4095u) == 0) {
        size_t k;
        for (k = 0; k < sizeof page; k++)
            page[k] = 'B';
        page[4100] = 0;
        expect(rt_strlen_ee((char *)page + 4080) == 20, "strlen-page");
        page[4094] = 0;
        expect(rt_strlen_ee((char *)page + 4090) == 4, "strlen-tail");
    } else {
        puts("page align skipped\n");
    }
#endif
}

static unsigned time_call(void (*fn)(void), unsigned reps)
{
    unsigned a, b, i;
    for (i = 0; i < 4; i++)
        fn();
    a = ee_count();
    for (i = 0; i < reps; i++)
        fn();
    b = ee_count();
    return b - a;
}

static void work_scalar_memcpy(void)
{
    rt_memcpy_scalar(dsta, srcb, 1024);
}
#if defined(RT_WIDE)
static void work_ee_memcpy(void) { rt_memcpy_ee(dstb, srcb, 1024); }
static void work_ee_memset(void) { rt_memset_ee(dstb, 0x2A, 1024); }
static void work_ee_memcmp(void) { (void)rt_memcmp_ee(srcb, dsta, 1024); }
static void work_ee_strlen(void) { (void)rt_strlen_ee(sa); }
static void work_ee_strcpy(void) { rt_strcpy_ee(sb, sa); }
static void work_ee_strcmp(void) { (void)rt_strcmp_ee(sa, sb); }
#endif
static void work_scalar_memset(void) { rt_memset_scalar(dsta, 0x2A, 1024); }
static void work_scalar_memcmp(void) { (void)rt_memcmp_scalar(srcb, dsta, 1024); }
static void work_scalar_strlen(void) { (void)rt_strlen(sa); }
static void work_scalar_strcpy(void) { rt_strcpy(sb, sa); }
static void work_scalar_strcmp(void) { (void)rt_strcmp(sa, sb); }

static void row(const char *name, const char *kind, unsigned ticks)
{
    puts("| ");
    puts(name);
    puts(" | ");
    puts(kind);
    puts(" | ");
    putu(ticks);
    puts(" |\n");
}

static void time_all(void)
{
    unsigned reps = 100;
    puts("ticks\n");
    puts("| function | kernel | ticks |\n");
    fill(srcb, 1024, 1);
    plant(sa, 64, -1);
    o_memcpy(sb, sa, 65);
    row("memcpy", "scalar", time_call(work_scalar_memcpy, reps));
    row("memset", "scalar", time_call(work_scalar_memset, reps));
    row("memcmp", "scalar", time_call(work_scalar_memcmp, reps));
    row("strlen", "scalar", time_call(work_scalar_strlen, reps));
    row("strcpy", "scalar", time_call(work_scalar_strcpy, reps));
    row("strcmp", "scalar", time_call(work_scalar_strcmp, reps));
#if defined(RT_WIDE)
    row("memcpy", RT_KIND, time_call(work_ee_memcpy, reps));
    row("memset", RT_KIND, time_call(work_ee_memset, reps));
    row("memcmp", RT_KIND, time_call(work_ee_memcmp, reps));
    row("strlen", RT_KIND, time_call(work_ee_strlen, reps));
    row("strcpy", RT_KIND, time_call(work_ee_strcpy, reps));
    row("strcmp", RT_KIND, time_call(work_ee_strcmp, reps));
#endif
}

int main(void)
{
#if defined(RT_MALTA)
    clear_bss();
#endif
    sio_init();
    puts("binary: ");
    puts(RT_BINARY);
    putc('\n');
    check_mem();
    check_strings();
    puts("checks: ");
    putu(g_check);
    puts(" fail: ");
    putu(g_fail);
    putc('\n');
    if (g_fail == 0)
        time_all();
    puts("[BENCH] run complete\n");
    return g_fail ? 1 : 0;
}
