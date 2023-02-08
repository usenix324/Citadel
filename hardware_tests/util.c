// See LICENSE for license details.

#include <stdint.h>
#include <string.h>
//#include <stdarg.h>
//#include <stdio.h>
//#include <limits.h>
//#include <sys/signal.h>
#include "util.h"

#define NUM_COUNTERS 2
static uintptr_t counters[NUM_COUNTERS];
static char* counter_names[NUM_COUNTERS];

void setStats(int enable)
{
  int i = 0;

  // set non-standard CSR stats
  asm volatile ("csrw 0x801, %0" :: "rK"(enable));

#define READ_CTR(name) do { \
    while (i >= NUM_COUNTERS) ; \
    uintptr_t csr = read_csr(name); \
    if (!enable) { csr -= counters[i]; counter_names[i] = #name; } \
    counters[i++] = csr; \
  } while (0)

  READ_CTR(mcycle);
  READ_CTR(minstret);

#undef READ_CTR
}
