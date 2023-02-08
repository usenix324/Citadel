#define NUM_HARTS     (2)

#define BOOT_ROM_BASE (0x1000)
#define BOOT_ROM_SIZE (0x1000)

#define RAM_BASE      (0x80000000)
#define RAM_SIZE      (0x80000000)

// Placement of SM in memory
#define SM_ADDR         0x80000000
#define HANDLER_LEN         0x4000
#define SM_LEN             0x20000

#define SM_STATE_ADDR   0x80030000
#define SM_STATE_LEN        0x3000

#define MEM_LOADER_BASE (0x1000000)

#define DEVICE_SECRET_BASE (0x1000000)
#define MSIP_BASE     (0x2000000)

#define PAGE_SIZE     (0x1000)
#define PAGE_SHIFT    (12)
