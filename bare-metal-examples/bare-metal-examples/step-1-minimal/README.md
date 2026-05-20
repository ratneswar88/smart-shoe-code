# Step 1: Minimal LED Blinky

This is the simplest possible bare metal program for STM32F429ZI.

## What it does

- Blinks the green LED (PB7) on the Nucleo-F429ZI board
- Uses minimal startup code
- No data initialization (no global variables)

## Files

- `startup.s` - Vector table and reset handler in assembly
- `main.c` - Simple LED blinking code
- `stm32f429zi.ld` - Linker script defining memory layout
- `Makefile` - Build automation

## Building

```bash
make
```

## Flashing to Nucleo board

```bash
# Using st-flash
make flash

# Or using OpenOCD
make flash-openocd
```

## Testing in QEMU

```bash
# Run directly
make qemu

# Or debug with GDB
# Terminal 1:
make qemu-gdb

# Terminal 2:
gdb-multiarch blinky.elf
(gdb) target remote :1234
(gdb) break main
(gdb) continue
```

## Understanding the Code

### Memory Map
- Flash: 0x08000000 - 0x081FFFFF (2MB)
- SRAM:  0x20000000 - 0x2002FFFF (192KB)

### Startup Sequence
1. CPU powers up, loads initial SP from 0x08000000
2. CPU loads Reset_Handler address from 0x08000004
3. Reset_Handler sets up stack and calls main()
4. main() enables GPIOB clock and configures PB7
5. Infinite loop toggles LED

### Register Access
All peripheral access is done through memory-mapped registers:
- RCC_AHB1ENR: Enable peripheral clocks
- GPIOB_MODER: Configure pin mode (input/output/alternate/analog)
- GPIOB_ODR: Output data register for toggling pins

## Next Steps

See step-2-startup for proper data initialization with .data and .bss sections.
