# Project name
PROJECT = blinky

# Target MCU
MCU = cortex-m4

# Toolchain
PREFIX = arm-none-eabi-
CC = $(PREFIX)gcc
AS = $(PREFIX)as
LD = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump
SIZE = $(PREFIX)size
GDB = gdb-multiarch

# Compiler flags
CFLAGS = -mcpu=$(MCU)
CFLAGS += -mthumb
CFLAGS += -mfloat-abi=hard
CFLAGS += -mfpu=fpv4-sp-d16
CFLAGS += -O2
CFLAGS += -Wall
CFLAGS += -Wextra
CFLAGS += -g
CFLAGS += -ffunction-sections
CFLAGS += -fdata-sections

# Assembler flags
ASFLAGS = -mcpu=$(MCU)
ASFLAGS += -mthumb
ASFLAGS += -g

# Linker flags
LDFLAGS = -T stm32f429zi.ld
LDFLAGS += -mcpu=$(MCU)
LDFLAGS += -mthumb
LDFLAGS += -mfloat-abi=hard
LDFLAGS += -mfpu=fpv4-sp-d16
LDFLAGS += -specs=nosys.specs
LDFLAGS += -nostartfiles
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -Wl,-Map=$(PROJECT).map

# Source files
C_SRCS = main.c
ASM_SRCS = startup_full.s

# Object files
OBJS = $(C_SRCS:.c=.o) $(ASM_SRCS:.s=.o)

# Default target
all: $(PROJECT).elf $(PROJECT).bin
	@echo "Build complete!"
	@$(SIZE) $(PROJECT).elf

# Compile C files
%.o: %.c
	@echo "Compiling $<..."
	@$(CC) $(CFLAGS) -c $< -o $@

# Assemble assembly files
%.o: %.s
	@echo "Assembling $<..."
	@$(AS) $(ASFLAGS) -c $< -o $@

# Link
$(PROJECT).elf: $(OBJS)
	@echo "Linking..."
	@$(LD) $(LDFLAGS) $(OBJS) -o $@

# Create binary
$(PROJECT).bin: $(PROJECT).elf
	@echo "Creating binary..."
	@$(OBJCOPY) -O binary $< $@

# Create hex
$(PROJECT).hex: $(PROJECT).elf
	@$(OBJCOPY) -O ihex $< $@

# Disassembly
disasm: $(PROJECT).elf
	@$(OBJDUMP) -D $< > $(PROJECT).dis

# Flash to board using st-flash
flash: $(PROJECT).bin
	@echo "Flashing to board..."
	@st-flash write $< 0x08000000

# Flash using OpenOCD
flash-openocd: $(PROJECT).elf
	@openocd -f board/st_nucleo_f4.cfg \
		-c "program $(PROJECT).elf verify reset exit"

# Debug with OpenOCD and GDB
debug:
	@echo "Starting OpenOCD in background..."
	@openocd -f board/st_nucleo_f4.cfg &
	@sleep 2
	@echo "Starting GDB..."
	@$(GDB) -ex "target remote :3333" \
		-ex "monitor reset halt" \
		-ex "load" \
		-ex "monitor reset init" \
		$(PROJECT).elf

# QEMU simulation
qemu: $(PROJECT).elf
	@echo "Running in QEMU..."
	@qemu-system-arm -M netduinoplus2 \
		-cpu cortex-m4 \
		-kernel $(PROJECT).elf \
		-nographic

# QEMU with GDB server
qemu-gdb: $(PROJECT).elf
	@echo "Starting QEMU with GDB server..."
	@qemu-system-arm -M netduinoplus2 \
		-cpu cortex-m4 \
		-kernel $(PROJECT).elf \
		-s -S \
		-nographic

# Clean
clean:
	@echo "Cleaning..."
	@rm -f *.o *.elf *.bin *.hex *.map *.dis

# Help
help:
	@echo "Available targets:"
	@echo "  all           - Build project (default)"
	@echo "  flash         - Flash using st-flash"
	@echo "  flash-openocd - Flash using OpenOCD"
	@echo "  debug         - Debug with OpenOCD and GDB"
	@echo "  qemu          - Run in QEMU emulator"
	@echo "  qemu-gdb      - Run QEMU with GDB server"
	@echo "  disasm        - Generate disassembly"
	@echo "  clean         - Remove build files"
	@echo "  help          - Show this help"

.PHONY: all flash flash-openocd debug qemu qemu-gdb disasm clean help
