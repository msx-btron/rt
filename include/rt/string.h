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

/* AArch64 NEON accelerators (same semantics as scalar). */
size_t      rt_strlen_neon(const char *s);
int         rt_strcmp_neon(const char *a, const char *b);
char       *rt_strchr_neon(const char *s, int c);

#endif
