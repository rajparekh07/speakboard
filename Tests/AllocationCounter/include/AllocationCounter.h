// Counts heap allocations on the calling thread, for the tests that prove a
// path allocates nothing. Test support only: never linked into the core.
#ifndef ALLOCATION_COUNTER_H
#define ALLOCATION_COUNTER_H

#include <stdbool.h>

// True when the counter works in this build: Linux with glibc. Elsewhere it
// counts nothing.
bool allocation_counter_available(void);

// Starts counting this thread's allocations from zero.
void allocation_counter_start(void);

// Stops counting and returns how many allocations this thread made since
// allocation_counter_start.
unsigned long allocation_counter_stop(void);

#endif
