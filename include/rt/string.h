#ifndef RT_STRING_H
#define RT_STRING_H

#include <stddef.h>

/* Scalar C99 string plane (tkl_* on rt.btron.pro).
   Bounded where a length is given. No locale, no heap.
   Word-aligned hot paths where useful; otherwise single-pass scans. */

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

/* Capacity-aware (Linux kernel style). Returns bytes that would be written
   excluding NUL, or n if truncated. Always NUL-terminates when n > 0. */
size_t      rt_strscpy(char *dst, const char *src, size_t n);
size_t      rt_strscat(char *dst, const char *src, size_t n);

/* Fixed-field pad: copy src into dst[0..width-1], pad with fill, no guarantee
   of trailing NUL if src length >= width. */
void        rt_strpad(char *dst, const char *src, size_t width, int fill);

#endif
