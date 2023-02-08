#include <sm.h>

void platform_memory_protection_exit_enclave(thread_metadata_t *thread_metadata) {

  write_csr(CSR_MEVBASE, thread_metadata->platform_csr.ev_base);
  write_csr(CSR_MEVMASK, thread_metadata->platform_csr.ev_mask);

  write_csr(CSR_MEMRBM, thread_metadata->platform_csr.memrbm);

  write_csr(CSR_MEPARBASE, thread_metadata->platform_csr.meparbase);
  write_csr(CSR_MEPARMASK, thread_metadata->platform_csr.meparmask);

  return;
}
