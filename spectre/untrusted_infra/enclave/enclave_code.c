#include <api_enclave.h>
#include <msgq.h>
#include <enclave_util.h>

#define SHARED_MEM_REG (0x8a000000)
#define SHARED_REQU_QUEUE ((queue_t *) SHARED_MEM_REG)
#define SHARED_RESP_QUEUE ((queue_t *) (SHARED_MEM_REG + sizeof(queue_t)))

#define SIZE_REGION (0x2000000)
#define SIZE_PAGE   (0x1000)

#define riscv_perf_cntr_begin() asm volatile("csrwi 0x801, 1")
#define riscv_perf_cntr_end() asm volatile("csrwi 0x801, 0")

// Array accessed by condition_load. It is also flushed from the L2 by the attacker.
volatile uint64_t *third_array= (uint64_t *) (SHARED_MEM_REG + SIZE_REGION - (2 * 256 * SIZE_PAGE));

// A condition that takes time to resolve based on a series of slow loads
// Computes idx < 4 in a convoluted way
bool condition_load(int idx) {
  //if(idx > 4) {riscv_perf_cntr_begin();} // These can be used to measure the number of cycles these computations take
  third_array[0 * SIZE_PAGE] = 0x4;
  third_array[1 * SIZE_PAGE] = third_array[0 * SIZE_PAGE] + 4;
  bool ret = (idx < (third_array[1 * SIZE_PAGE] - 4*1)); // Condition boils down to idx < 4
  //if(idx > 4) {
  //  riscv_perf_cntr_end();
  //  sm_exit_enclave();
  //}
  return ret;
}


// A condition that takes time to resolve based on a series of slow instructions (mult and div)
// Computes idx < 4 in a convoluted way
bool condition_mult(int idx) {
  //if(idx > 4) {riscv_perf_cntr_begin();}
  register uintptr_t a0 asm ("a0") = idx;
  register uintptr_t a1 asm ("a1") = 2;
  register uintptr_t a2 asm ("a2") = 0;
  uintptr_t val;
  asm volatile (" \
    mul a2, a0, a1; \n \
    mul a2, a2, a1; \n \
    mul a2, a2, a1; \n \
    mul a2, a2, a1; \n \
    div a2, a2, a1; \n \
    div a2, a2, a1; \n \
    div a2, a2, a1; \n \
    div %[val_reg], a2, a1; \n \
    " : [val_reg] "=&r" (val) : "r" (a0), "r" (a1), "r" (a2));
  bool ret = val < 4;
  //if(idx > 4) {
  //  riscv_perf_cntr_end();
  //  sm_exit_enclave();
  //}
  return ret;
}

// Array that contains the secret (code should not be able to access indexes > 4)
// Attack is easier with this array moved on the stack
char first_array[17] = "abcdeghijkl";
// Array in shared memory used for the side channel
char *second_array= (char *) (SHARED_MEM_REG + SIZE_REGION - (256 * SIZE_PAGE));

// Function executed by the enclave
void enclave_entry() {
  // Message queues for requests and responses
  queue_t * qreq = SHARED_REQU_QUEUE;
  queue_t * qres = SHARED_RESP_QUEUE;

  msg_t *m;
  int ret;

  while(true) {
    // Get messages from the request queue
    ret = pop(qreq, (void **) &m);
    // Abort if no messages
    if(ret != 0) continue;
    switch((m)->f) { // Switch depending on the function requested
      case F_SPECTER: ; // Specter-like gadget
                      int idx = (int) m->args[0];
                      int result = 0;
                      bool cond = condition_load(idx); // A condition equivalent to idx < 4
                      if(cond) {
                        //riscv_perf_cntr_begin();
                        char secret = first_array[idx]; // Secret access
                        result = second_array[secret * SIZE_PAGE]; // Transmitter
                        //riscv_perf_cntr_end();
                        //sm_exit_enclave();
                      }
                      m->args[1] = result; // Ensure a data dependence for compilation
                      m->ret = cond; // Used to check if the access was speculative
                      break;
      case F_EXIT: // Exit function
                      m->ret = 0;
                      m->done = true;
                      do {
                        ret = push(qres, m);
                      } while(ret != 0);
                      sm_exit_enclave();
      default:
                      break;
    } 
    m->done = true; // Function was executed
    do { // Push response to the queue
      ret = push(qres, m);
    } while(ret != 0);
  }
}
