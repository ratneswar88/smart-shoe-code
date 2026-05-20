# Quick Start Guide - ARM Bare Metal Programming

## 5-Minute Setup

### 1. Install Tools
```bash
sudo apt-get update
sudo apt-get install -y gcc-arm-none-eabi gdb-multiarch \
    openocd stlink-tools qemu-system-arm make git
```

### 2. Get the Code
```bash
git clone https://github.com/your-repo/bare-metal-arm.git
cd bare-metal-arm/step-1-minimal
```

### 3. Build
```bash
make
```

### 4a. Flash to Board (if you have hardware)
```bash
# Connect your Nucleo-F429ZI via USB
make flash
# Green LED should blink!
```

### 4b. Run in QEMU (no hardware needed)
```bash
make qemu
# Should see output (Ctrl+C to exit)
```

## Verify Your Setup

### Check Toolchain
```bash
arm-none-eabi-gcc --version
# Should show: arm-none-eabi-gcc (GNU Arm Embedded Toolchain ...) 10.3.1 or newer
```

### Check Board Connection
```bash
st-info --probe
# Should show: Found 1 stlink programmers
```

### Check QEMU
```bash
qemu-system-arm --version
# Should show: QEMU emulator version 6.2.0 or newer
```

## First Program

### Edit main.c
```c
#include <stdint.h>

#define GPIOB_ODR (*(volatile uint32_t *)0x40020414)
#define LED_PIN 7

int main(void) {
    // Enable clock and configure pin
    // (see full example for details)
    
    while(1) {
        GPIOB_ODR ^= (1 << LED_PIN);  // Toggle LED
        for(volatile int i=0; i<1000000; i++);  // Delay
    }
}
```

### Build and Flash
```bash
make clean
make
make flash
```

## Debug Your First Program

### Terminal 1: Start OpenOCD
```bash
openocd -f board/st_nucleo_f4.cfg
```

### Terminal 2: Connect GDB
```bash
gdb-multiarch blinky.elf

(gdb) target remote :3333
(gdb) monitor reset halt
(gdb) load
(gdb) break main
(gdb) continue
(gdb) info registers
(gdb) step
```

## Common Commands

| Command | Description |
|---------|-------------|
| `make` | Build project |
| `make flash` | Upload to board |
| `make clean` | Remove build files |
| `make qemu` | Run in emulator |
| `make debug` | Start debug session |
| `make help` | Show all options |

## Troubleshooting

### Build Fails
```bash
# Check toolchain
which arm-none-eabi-gcc
arm-none-eabi-gcc --version

# Reinstall if needed
sudo apt-get install --reinstall gcc-arm-none-eabi
```

### Flash Fails
```bash
# Check board connection
lsusb | grep -i stm
st-info --probe

# Try reset button on board
# Try different USB cable/port
```

### QEMU Fails
```bash
# Check QEMU installation
qemu-system-arm --version

# Run with explicit machine
qemu-system-arm -M netduinoplus2 -cpu cortex-m4 \
    -kernel blinky.elf -nographic
```

## Next Steps

1. ✅ Build and flash step-1-minimal
2. 📖 Read the tutorial document (ARM_Bare_Metal_Tutorial.docx)
3. 🔬 Try step-3-uart for serial communication
4. ⚡ Explore step-4-interrupts for timers
5. 🚀 Build your own project!

## Getting Help

- Read README.md in each example folder
- Check the comprehensive tutorial document
- Look at comments in source code
- Review STM32 reference manual
- Ask in community forums

---

Ready to start? Jump to step-1-minimal and run `make`!
