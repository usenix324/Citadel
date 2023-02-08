#include "util.h"
#include <stdio.h>

uint64_t random_byte() {
  return (read_csr( 0xCC0 ));
}

int main( int argc, char* argv[] ) {
    printf("Hi! Here are 16 readouts from the TRNG:\n");
    for (int i=0; i<16; i++) {
        printf("  %016llx\n", (long long unsigned)(random_byte()));
    }
    return 0;
}
