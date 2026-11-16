// Counts heap allocations by defining the C allocator's entry points in the
// test executable. On Linux a symbol the executable defines comes first in the
// dynamic linker's lookup, so every caller in the process, the Swift runtime
// and Foundation included, calls these instead of glibc's. Each one counts
// the call when the calling thread is counting, then forwards to glibc's own
// implementation (__libc_malloc and so on, which glibc exports for this).
//
// The count is per thread (__thread), so allocations by other tests running
// in parallel on other threads are not counted. Thread-local storage in the
// executable itself is set up before main and needs no allocation, so the
// counter cannot recurse into malloc.
//
// What it counts: malloc, calloc, realloc, memalign, aligned_alloc,
// posix_memalign, valloc and pvalloc. The Swift runtime allocates every class
// instance, closure context, box and array or string buffer through these
// (swift_slowAlloc calls malloc, or aligned_alloc for large alignments).
// What it cannot see: memory from mmap or brk called directly, the stack, and
// allocations on any thread but the counting one.
#include "AllocationCounter.h"

// errno.h comes first: through features.h it defines __GLIBC__ on glibc.
#include <errno.h>
#include <stddef.h>

#if defined(__linux__) && defined(__GLIBC__)

extern void *__libc_malloc(size_t size);
extern void *__libc_calloc(size_t count, size_t size);
extern void *__libc_realloc(void *pointer, size_t size);
extern void *__libc_memalign(size_t alignment, size_t size);
extern void *__libc_valloc(size_t size);
extern void *__libc_pvalloc(size_t size);

static __thread int counting;
static __thread unsigned long count;

static inline void note(void) {
    if (counting) {
        count++;
    }
}

void *malloc(size_t size) {
    note();
    return __libc_malloc(size);
}

void *calloc(size_t number, size_t size) {
    note();
    return __libc_calloc(number, size);
}

void *realloc(void *pointer, size_t size) {
    note();
    return __libc_realloc(pointer, size);
}

void *memalign(size_t alignment, size_t size) {
    note();
    return __libc_memalign(alignment, size);
}

void *aligned_alloc(size_t alignment, size_t size) {
    note();
    return __libc_memalign(alignment, size);
}

int posix_memalign(void **result, size_t alignment, size_t size) {
    note();
    if (alignment % sizeof(void *) != 0 || (alignment & (alignment - 1)) != 0) {
        return EINVAL;
    }
    void *pointer = __libc_memalign(alignment, size);
    if (pointer == NULL) {
        return ENOMEM;
    }
    *result = pointer;
    return 0;
}

void *valloc(size_t size) {
    note();
    return __libc_valloc(size);
}

void *pvalloc(size_t size) {
    note();
    return __libc_pvalloc(size);
}

bool allocation_counter_available(void) { return true; }

void allocation_counter_start(void) {
    count = 0;
    counting = 1;
}

unsigned long allocation_counter_stop(void) {
    counting = 0;
    return count;
}

#else

bool allocation_counter_available(void) { return false; }
void allocation_counter_start(void) {}
unsigned long allocation_counter_stop(void) { return 0; }

#endif
