# Secure Bootloader targets
# -------------------------

# Find the Root Directory
SB_DIR:=$(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Define compiler
CC=riscv64-unknown-elf-gcc
OBJCOPY=riscv64-unknown-elf-objcopy

# Define directories
SRC_DIR:=$(SB_DIR)/src
PLATFORM:=$(SRC_DIR)/platform
CRYPTO:=$(SRC_DIR)/crypto

# Define Targets
BUILD_DIR:=$(SB_DIR)/build
SB_BIN := $(BUILD_DIR)/secure_bootloader.bin
SB_ELF := $(BUILD_DIR)/secure_bootloader.elf

# QEMU
.PHONY: check_env
check_env:
ifndef SANCTUM_QEMU
	$(error SANCTUM_QEMU is undefined)
endif

# Define Sources
SB_SRCS := \
	$(SRC_DIR)/bootloader.c \
	$(SRC_DIR)/bootloader.S \
	$(PLATFORM)/platform.S \
	$(CRYPTO)/ed25519/fe.c \
	$(CRYPTO)/ed25519/ge.c \
	$(CRYPTO)/ed25519/keypair.c \
	$(CRYPTO)/ed25519/sc.c \
	$(CRYPTO)/ed25519/sha512.c \
	$(CRYPTO)/ed25519/sign.c \
	$(SRC_DIR)/clib/memcpy.c \

SB_LDS := $(SRC_DIR)/bootloader.lds

# Targets
$(BUILD_DIR):
	# create a build directory if one does not exist
	mkdir -p $(BUILD_DIR)

#DEBUG_FLAGS := -ggdb3
CFLAGS := -march=rv64g -mcmodel=medany -mabi=lp64 -fno-common -fno-tree-loop-distribute-patterns -std=gnu11 -Wall -Os $(DEBUG_FLAGS) -fvisibility=hidden -nostartfiles -nostdlib -static

#CFLAGS := -march=rv64g -mabi=lp64 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles

$(SB_ELF): $(BUILD_DIR) $(SB_LDS) $(SB_SRCS)
	# compile the secure bootloader ELF
	cd $(BUILD_DIR) && $(CC) -T $(SB_LDS) -I $(SRC_DIR) -I $(SRC_DIR)/clib -I $(CRYPTO) -I $(PLATFORM) $(CFLAGS) $(SB_SRCS) -o $(SB_ELF)

$(SB_BIN): $(SB_ELF)
# extract a binary image from the ELF
	cd $(BUILD_DIR) && $(OBJCOPY) -O binary --only-section=.text  $(SB_ELF) $(SB_BIN)

# Export target shorthand
.PHONY: secure_bootloader
secure_bootloader: $(SB_BIN)

.PHONY: secure_bootloader_test
secure_bootloader_test: check_env $(SB_BIN)
	$(SANCTUM_QEMU) -machine sanctum -m 2G -nographic -bios $(SB_BIN) -s -S

.PHONY: clean
clean:
	rm -rf $(SB_DIR)/build
