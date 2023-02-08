# Include the core environment definitions; this will set $(TOP).
include ../../py/mkenv.mk

# Include py core make definitions.
include $(TOP)/py/py.mk

# Set makefile-level MicroPython feature configurations.
MICROPY_ROM_TEXT_COMPRESSION ?= 0

# Define toolchain and other tools.
CROSS_COMPILE ?= riscv64-unknown-elf-

# Set CFLAGS.
CFLAGS += -I. -I$(TOP) -I$(BUILD)
CFLAGS += -Wall -Werror -std=gnu11 -nostdlib
CFLAGS += -march=rv64g -mcmodel=medany -mabi=lp64 -fno-common -fno-tree-loop-distribute-patterns -nostartfiles -nostdlib -static 
CSUPEROPT = -Os # save some code space for performance-critical code

# Select debugging or optimisation build.
DEBUG=1
ifeq ($(DEBUG), 1)
CFLAGS += -O0 -ggdb3
else
CFLAGS += -Os -DNDEBUG
CFLAGS += -fdata-sections -ffunction-sections
endif

# Set linker flags.
LDFLAGS += -T enclave.ld
#LDFLAGS += -T enclave.ld --gc-sections

# Define the required source files.
SRC_C += lib.c main.c system.c

# Define the required object files.
OBJ += $(PY_CORE_O)
OBJ += $(addprefix $(BUILD)/, $(SRC_C:.c=.o))

OBJ += $(BUILD)/entry.o
$(BUILD)/entry.o: enclave_entry.S
	$(Q)$(CC) -c $(CFLAGS) $(LDFLAGS) -o $@ $^

OBJ += $(BUILD)/setjmp.o
$(BUILD)/setjmp.o: setjmp.S
	$(Q)$(CC) -c $(CFLAGS) $(LDFLAGS) -o $@ $^

OBJ += $(BUILD)/longjmp.o
$(BUILD)/longjmp.o: longjmp.S
	$(Q)$(CC) -c $(CFLAGS) $(LDFLAGS) -o $@ $^

# Define the top-level target, the main firmware.
all: $(BUILD)/firmware.bin

$(BUILD)/firmware.elf: $(OBJ)
	$(ECHO) "LINK $@"
	$(Q)$(LD) $(LDFLAGS) -o $@ $^
	$(Q)$(SIZE) $@

$(BUILD)/firmware.bin: $(BUILD)/firmware.elf
	$(ECHO) "Create $@"
	$(Q)$(OBJCOPY) -O binary $^ $@

# Include remaining core make rules.
include $(TOP)/py/mkrules.mk
