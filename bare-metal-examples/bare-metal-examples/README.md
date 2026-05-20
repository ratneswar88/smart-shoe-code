# ARM Bare Metal Programming Examples
## Complete Tutorial for Nucleo-F429ZI and QEMU

This repository contains progressive examples for bare metal ARM Cortex-M4 programming, specifically targeting the STM32F429ZI microcontroller.

## 📚 Contents

- **Tutorial Document**: Comprehensive PDF/DOCX guide (see `ARM_Bare_Metal_Tutorial.docx`)
- **step-1-minimal**: Simplest LED blinky with minimal startup code
- **step-2-startup**: Full startup with .data and .bss initialization
- **step-3-uart**: UART communication and serial I/O
- **step-4-interrupts**: Interrupt handling with SysTick timer
- **qemu-examples**: QEMU-specific examples

## 🛠️ Requirements

### Software Tools
```bash
# Ubuntu/Debian
sudo apt-get install gcc-arm-none-eabi gdb-multiarch
sudo apt-get install openocd stlink-tools
sudo apt-get install qemu-system-arm
sudo apt-get install make git

# Verify installation
arm-none-eabi-gcc --version
qemu-system-arm --version
st-info --probe
```

### Hardware (optional)
- STM32 Nucleo-F429ZI development board
- USB cable (included with board)
- PC with USB port

## 🚀 Quick Start

### Using Real Hardware (Nucleo-F429ZI)

```bash
# Navigate to any example
cd step-1-minimal

# Build the project
make

# Flash to board
make flash

# Or use OpenOCD
make flash-openocd

# Debug with GDB
make debug
```

### Using QEMU Emulator

```bash
# Build and run in QEMU
cd step-1-minimal
make
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

## 📖 Learning Path

### Step 1: Minimal Blinky
**Learn**: Vector table, reset handler, GPIO basics
```bash
cd step-1-minimal
make flash
```
- Minimal startup code
- Direct register access
- LED blinking without libraries

### Step 2: Full Startup (Coming Soon)
**Learn**: Data initialization, BSS zeroing, proper startup sequence
- Copy .data from flash to RAM
- Zero .bss section
- Call C++ constructors (if any)

### Step 3: UART Communication
**Learn**: Serial I/O, alternate functions, clock configuration
```bash
cd step-3-uart
make flash
minicom -D /dev/ttyACM0 -b 115200
```
- USART3 initialization
- GPIO alternate function configuration
- Character and string I/O
- Interactive commands

### Step 4: Interrupt Handling
**Learn**: ISR, SysTick timer, NVIC, interrupt priorities
```bash
cd step-4-interrupts
make flash
```
- SysTick timer setup (1ms interrupts)
- LED toggle in ISR
- Non-blocking delays
- Status reporting via UART

## 🔧 Project Structure

Each example contains:
```
example-folder/
├── main.c              # Main application code
├── startup.s           # Assembly startup code
├── stm32f429zi.ld     # Linker script
├── Makefile           # Build automation
└── README.md          # Example-specific documentation
```

## 📝 Makefile Targets

All examples support these make targets:

| Target | Description |
|--------|-------------|
| `make` or `make all` | Build the project |
| `make flash` | Flash using st-flash |
| `make flash-openocd` | Flash using OpenOCD |
| `make debug` | Start OpenOCD + GDB debug session |
| `make qemu` | Run in QEMU emulator |
| `make qemu-gdb` | Run QEMU with GDB server |
| `make disasm` | Generate disassembly listing |
| `make clean` | Remove build files |
| `make help` | Show all available targets |

## 🎯 Key Concepts Covered

### Memory Map
- **Flash**: 0x08000000 - 0x081FFFFF (2 MB)
- **SRAM**: 0x20000000 - 0x2002FFFF (192 KB)
- **Peripherals**: 0x40000000 - 0x5FFFFFFF

### ARM Cortex-M4 Features
- **Registers**: R0-R12 (general), R13 (SP), R14 (LR), R15 (PC)
- **Modes**: Thread and Handler modes
- **Interrupts**: NVIC with 82 external interrupts
- **SysTick**: 24-bit timer for OS scheduling

### Peripheral Access
All peripherals accessed via memory-mapped registers:
```c
#define RCC_BASE      0x40023800
#define RCC_AHB1ENR   (*(volatile uint32_t *)(RCC_BASE + 0x30))

// Enable GPIOB clock
RCC_AHB1ENR |= (1 << 1);
```

## 🐛 Debugging Tips

### Using GDB with OpenOCD
```bash
# Terminal 1: Start OpenOCD
openocd -f board/st_nucleo_f4.cfg

# Terminal 2: Connect GDB
gdb-multiarch your_program.elf
(gdb) target remote :3333
(gdb) monitor reset halt
(gdb) load
(gdb) break main
(gdb) continue
```

### Useful GDB Commands
```gdb
info registers          # Show all registers
x/10x 0x20000000       # Examine memory (hex)
disassemble main       # Disassemble function
backtrace              # Show call stack
step                   # Step one instruction
next                   # Step over function
continue               # Continue execution
```

### Common Issues

**LED doesn't blink**
- Check clock is enabled: `RCC_AHB1ENR |= (1 << 1);`
- Verify pin configuration: `GPIOB_MODER`
- Confirm correct LED pin (PB7 for Nucleo-F429ZI)

**UART not working**
- Verify baud rate calculation
- Check GPIO alternate function settings
- Confirm TX/RX pin numbers (PD8/PD9)
- Test with `minicom` or `screen`

**Hard Fault**
- Check stack size in linker script
- Verify pointer initialization
- Look for array out-of-bounds
- Use hard fault handler to dump registers

## 📚 Resources

### Official Documentation
- [STM32F429ZI Reference Manual (RM0090)](https://www.st.com/resource/en/reference_manual/dm00031020.pdf)
- [Cortex-M4 Generic User Guide](https://developer.arm.com/documentation/dui0553/latest)
- [STM32F4 Programming Manual (PM0214)](https://www.st.com/resource/en/programming_manual/dm00046982.pdf)

### Toolchain
- [GNU ARM Embedded Toolchain](https://developer.arm.com/downloads/-/gnu-rm)
- [OpenOCD Documentation](http://openocd.org/documentation/)
- [QEMU Documentation](https://www.qemu.org/docs/master/)

### Community
- [STM32 Community Forums](https://community.st.com/)
- [ARM Community](https://community.arm.com/)

## 🔬 Hardware Reference

### Nucleo-F429ZI Pinout
| Function | Pin | Description |
|----------|-----|-------------|
| LED Green | PB7 | User LED (LD1) |
| LED Blue | PB7 | Same as green |
| LED Red | PB14 | User LED (LD3) |
| Button | PC13 | User button (B1) |
| USART3 TX | PD8 | Connected to ST-Link VCP |
| USART3 RX | PD9 | Connected to ST-Link VCP |

### Clock Configuration
- HSI: 16 MHz (internal oscillator, default)
- HSE: 8 MHz (external crystal)
- PLL: Up to 180 MHz (maximum)
- Default after reset: HSI (16 MHz)

## 🎓 Next Steps

After completing these examples, you can:
1. Implement additional peripherals (I2C, SPI, ADC, DAC)
2. Add a simple scheduler (cooperative or preemptive)
3. Integrate FreeRTOS or other RTOS
4. Implement USB device stack
5. Add Ethernet communication
6. Build complex applications (data logger, motor controller, etc.)

## 📄 License

This tutorial and code examples are provided for educational purposes.
Feel free to use, modify, and distribute with attribution.

## 🤝 Contributing

Found an issue or want to improve the examples?
- Report bugs and issues
- Suggest improvements
- Submit pull requests
- Share your projects built with these examples

## 📧 Support

For questions and discussion:
- Check the tutorial document for detailed explanations
- Read the README in each example folder
- Refer to official STM32 documentation
- Ask in ARM or STM32 community forums

---

**Happy Bare Metal Programming! 🚀**
