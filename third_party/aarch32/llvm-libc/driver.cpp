/* One-function driver used to emit memcpy-m0.S, memcpy-mid.S, and
   memcpy-m7.S. The command is in those files and in SOURCES.md.
   Apache-2.0 WITH LLVM-exception, same as the header it includes. */
#include "src/string/memory_utils/arm/inline_memcpy.h"

extern "C" void *memcpy(void *dst, const void *src, size_t n) {
  auto *d = static_cast<LIBC_NAMESPACE::cpp::byte *>(dst);
  auto *s = static_cast<const LIBC_NAMESPACE::cpp::byte *>(src);
  LIBC_NAMESPACE::inline_memcpy_arm(d, s, n);
  return dst;
}
