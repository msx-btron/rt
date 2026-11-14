#ifndef RT_STRING_H
#define RT_STRING_H

#include <stddef.h>

/* Scalar C99 string plane (tkl_* on rt.btron.pro).
   Bounded where a length is given. No locale, no heap. */

size_t      rt_strlen(const char *s);
size_t      rt_strnlen(const char *s, size_t n);

char       *rt_strcpy(char *dst, const char *src);
char       *rt_strncpy(char *dst, const char *src, size_t n);
char       *rt_strcat(char *dst, const char *src);
char       *rt_strncat(char *dst, const char *src, size_t n);

int         rt_strcmp(const char *a, const char *b);
int         rt_strncmp(const char *a, const char *b, size_t n);

char       *rt_strchr(const char *s, int c);
char       *rt_strrchr(const char *s, int c);
char       *rt_strstr(const char *hay, const char *needle);
char       *rt_strpbrk(const char *s, const char *accept);

size_t      rt_strscpy(char *dst, const char *src, size_t n);
size_t      rt_strscat(char *dst, const char *src, size_t n);

void        rt_strpad(char *dst, const char *src, size_t width, int fill);

size_t      rt_strlen_neon(const char *s);
int         rt_strcmp_neon(const char *a, const char *b);
char       *rt_strchr_neon(const char *s, int c);

/* RVV, one object per XLEN. A NUL scan uses a fault-only-first load.
   Bounded calls stop at n. memmove is not in this set. */
size_t      rt_strlen_rvv(const char *s);
size_t      rt_strnlen_rvv(const char *s, size_t n);
char       *rt_strcpy_rvv(char *dst, const char *src);
char       *rt_strncpy_rvv(char *dst, const char *src, size_t n);
char       *rt_strcat_rvv(char *dst, const char *src);
char       *rt_strncat_rvv(char *dst, const char *src, size_t n);
int         rt_strcmp_rvv(const char *a, const char *b);
int         rt_strncmp_rvv(const char *a, const char *b, size_t n);
char       *rt_strchr_rvv(const char *s, int c);
char       *rt_strrchr_rvv(const char *s, int c);
char       *rt_strstr_rvv(const char *hay, const char *needle);
char       *rt_strpbrk_rvv(const char *s, const char *accept);
size_t      rt_strscpy_rvv(char *dst, const char *src, size_t n);
size_t      rt_strscat_rvv(char *dst, const char *src, size_t n);
void        rt_strpad_rvv(char *dst, const char *src, size_t width, int fill);

#endif
