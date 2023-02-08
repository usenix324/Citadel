#include <stdbool.h>
#include <csr/csr.h>
#include <sm.h>

extern void * payload_ptr;
extern uintptr_t stack_ptr;
extern uint8_t trap_vector_from_untrusted;

#ifndef SIGNING_ENCLAVE_MEASUREMENT
#define SIGNING_ENCLAVE_MEASUREMENT {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}
#endif

void sm_init(uintptr_t fdt_boot_addr) {
  sm_state_t * sm = get_sm_state_ptr();
  
  sm->boot_process_stage = BOOT_INIT_NOT_DONE;

  // IMPORTANT: this will be run by *all* cores
  uintptr_t core_id = platform_get_core_id();
  if (core_id == 0) {
    
    console_init();

    printm("Enter sm_init\n");
    // Initialize core metadata
    for ( int i=0; i<NUM_CORES; i++ ) {
      sm->cores[i].owner = OWNER_UNTRUSTED;
      sm->cores[i].thread = ENCLAVE_THREAD_NONE;
      sm->cores[i].hls_ptr = ((uintptr_t) &stack_ptr) - (i * STACK_SIZE) - HLS_SIZE; 
      unlock_core(i); // Ensure cores aren't locked
    }

    // Initialize region metadata : untrusted SW owns all regions that do not include SM code.
    // Initialize untrusted metadata : untrusted SW is allowed access to all regions that do not include SM code.
    for ( int i=0; i<NUM_REGIONS; i++ ) {
      bool region_doesnt_include_sm = (uint64_t)region_id_to_addr(i) > (SM_ADDR+SM_LEN);
      if(region_doesnt_include_sm) {
        sm->untrusted_regions.flags[i] = true;
      }
      sm->regions[i].owner = region_doesnt_include_sm ? OWNER_UNTRUSTED : OWNER_SM;
      sm->regions[i].type = REGION_TYPE_UNTRUSTED;
      sm->regions[i].state = REGION_STATE_OWNED;
      unlock_region(i); // Ensure cores aren't locked. the SM must be initialized in a vaccum, with only one thread running, so this is not dangerous.
    }

    // Initialize signing enclave measurement
    asm volatile("fence");
    const uint8_t signing_enclave_measurement[64] = SIGNING_ENCLAVE_MEASUREMENT;
    asm volatile("fence");
    memcpy( sm->signing_enclave_measurement.bytes, signing_enclave_measurement, sizeof(signing_enclave_measurement) );

    // Initialize untrusted mailboxes : all are empty and unused.
    for ( int i=0; i<NUM_UNTRUSTED_MAILBOXES; i++ ) {
      sm->untrusted_mailboxes[i].state = ENCLAVE_MAILBOX_STATE_UNUSED;
    }

    // Unlock the SM untrusted state
    unlock_untrusted_state();

    // Initialize shared platform state
    platform_init();

    // Initialize kernel
    kernel_init(fdt_boot_addr);
    printm("kernel_init done\n");

    // Resume other cores
  /*
    uintptr_t hart_mask = 0xf;
    send_ipi_many(&hart_mask, IPI_SOFT);
    printm("IPIs sent\n");
  */
    sm->boot_process_stage = BOOT_INIT_DONE;

  } else {
    // All cores but core 0 sleep until shared state is initialized
    //platform_wait_for_interrupt();
    while(sm->boot_process_stage != BOOT_INIT_DONE) {};
  }

  // Initialize platform core state
  platform_core_init();

  // Initialize memory protection
  platform_initialize_memory_protection(sm);

  // Walk the device tree and get its address
  uintptr_t fdt_os_addr = platform_get_device_tree_addr();

  // payload must set its own stack pointer.
  platform_jump_to_untrusted( UNTRUSTED_ENTRY, 0, core_id, fdt_os_addr);
}
