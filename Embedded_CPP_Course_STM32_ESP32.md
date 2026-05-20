# Embedded C++ Course: STM32 & ESP32
### A Comprehensive Guide for Embedded and IoT Engineers

---

# TABLE OF CONTENTS

## PART 1 — FOUNDATIONS OF EMBEDDED C++
1. Why C++ in Embedded Systems
2. C++ vs C in Embedded Context
3. Essential C++ Features for Embedded
4. Memory Model and Placement New
5. RAII and Resource Management
6. Templates and Constexpr

## PART 2 — STM32 WITH C++
7. STM32 Architecture Overview
8. Toolchain Setup (STM32CubeIDE / CMake + GCC)
9. GPIO: Blink and Beyond
10. UART Communication
11. Timers and PWM
12. I2C and SPI Peripherals
13. Interrupts and NVIC
14. DMA Transfers
15. FreeRTOS on STM32 with C++
16. Low-Power Modes
17. STM32 Practice Projects

## PART 3 — ESP32 WITH C++
18. ESP32 Architecture Overview
19. Toolchain Setup (ESP-IDF + CMake)
20. GPIO and Basic I/O
21. UART, I2C, and SPI
22. FreeRTOS on ESP32 (Dual-Core)
23. WiFi and TCP/IP Stack
24. BLE GATT Server/Client
25. NVS and LittleFS Storage
26. OTA Firmware Updates (MCUboot)
27. Low-Power and Deep Sleep
28. ESP32 Practice Projects

## PART 4 — ADVANCED TOPICS
29. State Machines in C++
30. Ring Buffers and Lock-Free Structures
31. Unit Testing Embedded Code
32. Production-Grade Fault Handling

---

# PART 1 — FOUNDATIONS OF EMBEDDED C++

---

## Chapter 1: Why C++ in Embedded Systems

### 1.1 The Historical Debate

For decades, embedded firmware was written exclusively in C or assembly. C offered low-level memory control, predictable code size, and zero overhead. C++ was considered "too heavy" for microcontrollers due to concerns about:

- Virtual function tables (vtables) in flash
- Exceptions and RTTI increasing binary size
- Dynamic memory allocation via `new`/`delete`
- Hidden costs from operator overloading

Modern embedded C++ **surgically avoids** these pitfalls while gaining:

| C++ Feature | Embedded Benefit |
|---|---|
| Classes & encapsulation | Peripheral drivers as self-contained objects |
| Templates | Zero-overhead generic data structures |
| `constexpr` | Compile-time computation, no runtime cost |
| RAII | Automatic resource management (mutexes, DMA) |
| Namespaces | Avoids naming collisions in large codebases |
| Operator overloading | Readable register bitfield manipulation |
| `static_assert` | Compile-time hardware constraint checking |

### 1.2 What to Avoid in Bare-Metal C++

```cpp
// ❌ NEVER use these in bare-metal embedded code
#include <iostream>     // Brings in heavy runtime, heap
throw std::exception(); // Exceptions require stack unwinding tables
new MyClass();          // Dynamic allocation → heap fragmentation
virtual void foo();     // vtable in flash (acceptable sometimes, but measure it)
typeid(obj);            // RTTI — disable with -fno-rtti
```

```cmake
# Always compile with these flags for embedded C++
add_compile_options(
  -fno-exceptions       # Disable exception support
  -fno-rtti             # Disable run-time type info
  -fno-use-cxa-atexit   # No global destructor table
  -ffunction-sections   # Dead code elimination
  -fdata-sections
)
add_link_options(-Wl,--gc-sections)
```

---

## Chapter 2: C++ vs C in Embedded Context

### 2.1 Struct vs Class

```cpp
// C-style peripheral handle
typedef struct {
    uint32_t base_addr;
    uint32_t baud_rate;
    uint8_t  tx_buf[64];
} UART_Handle_t;

void UART_Init(UART_Handle_t* h, uint32_t addr, uint32_t baud);
void UART_Send(UART_Handle_t* h, const uint8_t* data, size_t len);

// C++ equivalent — encapsulated, harder to misuse
class UartDriver {
public:
    UartDriver(uint32_t base_addr, uint32_t baud_rate);
    void send(const uint8_t* data, size_t len);
    bool isReady() const;

private:
    volatile uint32_t* const reg_;   // Points directly to hardware registers
    uint32_t baud_;
    uint8_t tx_buf_[64];
    uint8_t tx_head_, tx_tail_;
};
```

### 2.2 Type Safety: Enums

```cpp
// C: error-prone, no type safety
#define GPIO_MODE_INPUT  0
#define GPIO_MODE_OUTPUT 1

// C++11 Scoped Enum: type-safe, no namespace pollution
enum class GpioMode : uint8_t {
    Input       = 0,
    Output      = 1,
    AlternateFunc = 2,
    Analog      = 3
};

void configurePin(GpioMode mode) {
    // Compiler error if wrong enum type is passed
}

configurePin(GpioMode::Output);  // ✅ Clear and safe
configurePin(1);                  // ❌ Compile error
```

### 2.3 Namespaces

```cpp
// bsp/gpio.hpp
namespace bsp {
namespace gpio {

    class Pin {
    public:
        Pin(uint8_t port, uint8_t pin, GpioMode mode);
        void set();
        void clear();
        void toggle();
        bool read() const;
    };

} // namespace gpio
} // namespace bsp

// Usage
bsp::gpio::Pin led(GPIOC, 13, GpioMode::Output);
led.toggle();
```

---

## Chapter 3: Essential C++ Features for Embedded

### 3.1 `constexpr` — Compile-Time Constants

```cpp
// These are evaluated at compile time — zero runtime overhead
constexpr uint32_t APB1_CLK_HZ = 84'000'000UL;   // C++14 digit separator
constexpr uint32_t UART_BAUD    = 115200UL;
constexpr uint32_t BRR_VALUE    = APB1_CLK_HZ / UART_BAUD;

// constexpr function — computed at compile time if args are constexpr
constexpr uint32_t calcBRR(uint32_t apb_clk, uint32_t baud) {
    return apb_clk / baud;
}

static_assert(calcBRR(84'000'000, 115200) == 729, "BRR mismatch!");
```

### 3.2 `static_assert` — Compile-Time Checks

```cpp
// Enforce hardware constraints at build time
template<size_t N>
class RingBuffer {
    static_assert(N > 0,          "Buffer size must be > 0");
    static_assert((N & (N-1)) == 0, "Buffer size must be power of 2");
    uint8_t buf_[N];
    uint8_t head_, tail_;
};

// Ensure struct fits in a single SPI transaction
struct SensorPacket {
    uint16_t accel_x, accel_y, accel_z;
    uint16_t gyro_x,  gyro_y,  gyro_z;
};
static_assert(sizeof(SensorPacket) == 12, "SensorPacket layout mismatch");
```

### 3.3 `volatile` and Memory-Mapped Registers

```cpp
// Hardware registers MUST be volatile
// Without volatile, compiler may cache the value in a register

struct USART_Regs {
    volatile uint32_t SR;   // Status Register
    volatile uint32_t DR;   // Data Register
    volatile uint32_t BRR;  // Baud Rate Register
    volatile uint32_t CR1;  // Control Register 1
    volatile uint32_t CR2;
    volatile uint32_t CR3;
    volatile uint32_t GTPR;
};

// Map struct onto hardware address
USART_Regs* const USART1 = reinterpret_cast<USART_Regs*>(0x40011000UL);

// Now register access is readable AND correct
USART1->CR1 |= (1u << 13);    // Enable USART
while (!(USART1->SR & (1u << 7)));  // Wait TXE
USART1->DR = 'A';
```

### 3.4 Bit Manipulation with Struct Bitfields

```cpp
// Register bitfield struct — readable AND zero-overhead
union USART_CR1 {
    struct {
        uint32_t SBK   : 1;
        uint32_t RWU   : 1;
        uint32_t RE    : 1;  // Receiver Enable
        uint32_t TE    : 1;  // Transmitter Enable
        uint32_t IDLEIE: 1;
        uint32_t RXNEIE: 1;
        uint32_t TCIE  : 1;
        uint32_t TXEIE : 1;
        uint32_t PEIE  : 1;
        uint32_t PS    : 1;
        uint32_t PCE   : 1;
        uint32_t WAKE  : 1;
        uint32_t M     : 1;
        uint32_t UE    : 1;  // USART Enable
        uint32_t       : 18; // Reserved
    } bits;
    uint32_t word;
};

volatile USART_CR1* cr1 = reinterpret_cast<volatile USART_CR1*>(0x4001100C);
cr1->bits.UE = 1;  // Enable USART — no magic numbers!
cr1->bits.TE = 1;
cr1->bits.RE = 1;
```

---

## Chapter 4: Memory Model and Placement New

### 4.1 Embedded Memory Regions

```
Flash (ROM):  Code (.text), read-only data (.rodata), const
SRAM (RAM):   Stack, .bss (zeroed globals), .data (initialized globals), heap
CCM/TCM:      Tightly coupled memory — zero-wait-state access (STM32F4+)
```

```cpp
// Place time-critical ISR data in CCM (STM32 specific)
__attribute__((section(".ccmram")))
static volatile uint32_t encoder_count;

// Place a large lookup table in Flash (saves RAM)
static const uint8_t sine_table[256] __attribute__((section(".rodata"))) = {
    128, 131, 134, 137, /* ... */
};
```

### 4.2 Placement New — Objects Without Heap

```cpp
// Problem: new/delete are forbidden (heap fragmentation)
// Solution: Placement new — construct object in pre-allocated buffer

#include <new>  // for placement new operator

// Static storage — allocated in .bss, no heap
alignas(UartDriver) static uint8_t uart1_storage[sizeof(UartDriver)];

UartDriver* uart1 = nullptr;

void system_init() {
    // Construct UartDriver IN the static buffer — no heap involved
    uart1 = new (uart1_storage) UartDriver(USART1_BASE, 115200);
}

void system_deinit() {
    // Explicit destructor call (no delete — we didn't heap-allocate)
    uart1->~UartDriver();
    uart1 = nullptr;
}
```

### 4.3 Static Object Pool

```cpp
// Generic object pool — pre-allocates N objects of type T
template<typename T, size_t N>
class ObjectPool {
public:
    template<typename... Args>
    T* acquire(Args&&... args) {
        for (auto& slot : slots_) {
            if (!slot.used) {
                slot.used = true;
                return new (&slot.storage) T(args...);  // Placement new
            }
        }
        return nullptr;  // Pool exhausted
    }

    void release(T* obj) {
        obj->~T();
        for (auto& slot : slots_) {
            if (reinterpret_cast<T*>(&slot.storage) == obj) {
                slot.used = false;
                return;
            }
        }
    }

private:
    struct Slot {
        alignas(T) uint8_t storage[sizeof(T)];
        bool used = false;
    };
    Slot slots_[N];
};

// Usage: pool of 4 UART drivers — no heap
ObjectPool<UartDriver, 4> uart_pool;
auto* uart = uart_pool.acquire(USART1_BASE, 115200U);
```

---

## Chapter 5: RAII and Resource Management

RAII (Resource Acquisition Is Initialization) ties resource lifetime to object scope. In embedded, this is invaluable for:
- Mutex lock/unlock
- Critical sections (interrupt disable/enable)
- DMA channel acquire/release
- SPI chip select assert/deassert

### 5.1 Critical Section Guard

```cpp
// Without RAII — error-prone, easy to forget re-enable
void bad_function() {
    __disable_irq();
    shared_counter++;
    if (error_condition) return;   // ← BUG: IRQ never re-enabled!
    __enable_irq();
}

// With RAII — interrupts always restored when guard goes out of scope
class CriticalSection {
public:
    CriticalSection()  { primask_ = __get_PRIMASK(); __disable_irq(); }
    ~CriticalSection() { __set_PRIMASK(primask_); }

    // Non-copyable, non-movable
    CriticalSection(const CriticalSection&) = delete;
    CriticalSection& operator=(const CriticalSection&) = delete;

private:
    uint32_t primask_;
};

void good_function() {
    CriticalSection cs;   // IRQ disabled here
    shared_counter++;
    if (error_condition) return;  // ✅ Destructor fires, IRQ re-enabled
    // Destructor fires here too
}
```

### 5.2 SPI Chip Select RAII

```cpp
class SpiDevice {
public:
    SpiDevice(GpioPin& cs_pin, SpiPort& spi)
        : cs_(cs_pin), spi_(spi) {}

    // Transaction guard — RAII CS assertion
    class Transaction {
    public:
        explicit Transaction(SpiDevice& dev) : dev_(dev) {
            dev_.cs_.clear();  // Assert CS (active low)
        }
        ~Transaction() {
            dev_.cs_.set();    // Deassert CS
        }
        void write(uint8_t byte) { dev_.spi_.transfer(byte); }
        uint8_t read()           { return dev_.spi_.transfer(0xFF); }

    private:
        SpiDevice& dev_;
    };

    Transaction begin() { return Transaction(*this); }

private:
    GpioPin& cs_;
    SpiPort& spi_;
};

// Usage
void readIMU() {
    auto txn = imu_device.begin();  // CS asserted
    txn.write(0x3B | 0x80);         // Read from reg 0x3B
    int16_t ax = (txn.read() << 8) | txn.read();
    // CS automatically deasserted when txn goes out of scope
}
```

---

## Chapter 6: Templates and Constexpr

### 6.1 Generic Ring Buffer (Zero Overhead)

```cpp
template<typename T, size_t N>
class RingBuffer {
    static_assert((N & (N - 1)) == 0, "N must be power of 2");
    static constexpr size_t MASK = N - 1;

public:
    bool push(const T& item) {
        if (full()) return false;
        buf_[head_++ & MASK] = item;
        return true;
    }

    bool pop(T& item) {
        if (empty()) return false;
        item = buf_[tail_++ & MASK];
        return true;
    }

    bool empty() const { return head_ == tail_; }
    bool full()  const { return (head_ - tail_) == N; }
    size_t size()  const { return head_ - tail_; }

private:
    T      buf_[N];
    size_t head_ = 0, tail_ = 0;
};

// Completely resolved at compile time — no virtual dispatch, no overhead
RingBuffer<uint8_t, 256> uart_rx_buf;  // 256-byte UART receive buffer
RingBuffer<SensorPacket, 32> imu_buf;  // 32-packet IMU queue
```

### 6.2 Type-Safe Register Abstraction

```cpp
// Wrap raw register address with type safety
template<uint32_t ADDR, typename T = uint32_t>
struct MemReg {
    static volatile T& ref() {
        return *reinterpret_cast<volatile T*>(ADDR);
    }
    static void write(T val)          { ref() = val; }
    static T    read()                 { return ref(); }
    static void setBits(T mask)        { ref() |= mask; }
    static void clearBits(T mask)      { ref() &= ~mask; }
    static bool testBit(uint8_t bit)   { return (ref() >> bit) & 1u; }
};

// Define peripheral registers — zero overhead, fully inlined
using GPIOC_ODR  = MemReg<0x40020814>;
using USART1_DR  = MemReg<0x40011004>;
using USART1_SR  = MemReg<0x40011000>;

// Usage
GPIOC_ODR::setBits(1u << 13);          // Set PC13
while (!USART1_SR::testBit(7));         // Wait TXE
USART1_DR::write('A');
```

---

# PART 2 — STM32 WITH C++

---

## Chapter 7: STM32 Architecture Overview

### 7.1 Core and Bus Architecture

```
┌────────────────────────────────────────────────────────┐
│                  Cortex-M4 Core (168 MHz)              │
│   FPU (single precision)  │  MPU (8 regions)           │
│   Thumb-2 ISA             │  NVIC (240 IRQs, 16 prio)  │
└──────────────────┬─────────────────────────────────────┘
                   │ AHB Bus Matrix (up to 168 MHz)
       ┌───────────┴───────────────────┐
       │                               │
   AHB1 Bus                       AHB2 Bus
  (GPIO A-I,                     (USB OTG FS,
   DMA1/2,                        Camera)
   Ethernet)
       │
   APB1 Bus (42 MHz)         APB2 Bus (84 MHz)
  (USART2-5, SPI2/3,         (USART1/6, SPI1,
   I2C1-3, TIM2-7)            TIM1/8-11, ADC)
```

### 7.2 Clock System (RCC)

```cpp
// STM32F4 typical clock configuration
// HSE 8 MHz → PLL → 168 MHz SYSCLK

void SystemClock_Config() {
    RCC->CR |= RCC_CR_HSEON;                   // Enable HSE
    while (!(RCC->CR & RCC_CR_HSERDY));        // Wait HSE ready

    // Configure PLL: PLLM=8, PLLN=336, PLLP=2, PLLQ=7
    // f_VCO = 8MHz / 8 * 336 = 336 MHz
    // SYSCLK = 336 / 2 = 168 MHz
    // USB/SDIO = 336 / 7 = 48 MHz
    RCC->PLLCFGR = RCC_PLLCFGR_PLLSRC_HSE |
                   (8u  << RCC_PLLCFGR_PLLM_Pos) |
                   (336u << RCC_PLLCFGR_PLLN_Pos) |
                   (0u  << RCC_PLLCFGR_PLLP_Pos) | // PLLP = 2
                   (7u  << RCC_PLLCFGR_PLLQ_Pos);

    RCC->CR |= RCC_CR_PLLON;
    while (!(RCC->CR & RCC_CR_PLLRDY));

    FLASH->ACR |= FLASH_ACR_LATENCY_5WS;      // 5 wait states for 168 MHz
    RCC->CFGR  |= RCC_CFGR_SW_PLL;            // Select PLL as SYSCLK
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_PLL);

    // AHB=168MHz, APB1=42MHz, APB2=84MHz
    RCC->CFGR |= RCC_CFGR_HPRE_DIV1 |
                 RCC_CFGR_PPRE1_DIV4 |
                 RCC_CFGR_PPRE2_DIV2;
}
```

### 7.3 HAL vs LL vs Register-Direct

| Approach | Code Size | Speed | Portability | Use Case |
|---|---|---|---|---|
| HAL (High-Level) | Largest | Slowest | Best | Prototyping, non-critical paths |
| LL (Low-Level) | Medium | Fast | Good | Most production code |
| Register Direct | Smallest | Fastest | None | ISRs, ultra-tight loops |

---

## Chapter 8: Toolchain Setup

### 8.1 STM32CubeIDE Project with C++ Support

```
1. New STM32 Project → Select MCU (e.g., STM32F411CEU6)
2. Project name → Check "C++ project"
3. In Project Properties → C/C++ Build → Settings:
   - C++ Compiler → Miscellaneous: add -fno-exceptions -fno-rtti
4. Rename main.c → main.cpp (or add .cpp files to src/)
5. All HAL code in .c files still callable from C++
```

### 8.2 CMake + ARM GCC (Platform Independent)

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.22)
project(stm32f4_app LANGUAGES C CXX ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# ARM Cortex-M4 + FPU flags
set(CPU_FLAGS "-mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard")

set(COMMON_FLAGS "${CPU_FLAGS} -ffunction-sections -fdata-sections -Wall")
set(CMAKE_C_FLAGS   "${COMMON_FLAGS} -std=c11")
set(CMAKE_CXX_FLAGS "${COMMON_FLAGS} -std=c++17 -fno-exceptions -fno-rtti -fno-use-cxa-atexit")

add_executable(${PROJECT_NAME}
    src/main.cpp
    src/drivers/uart_driver.cpp
    src/drivers/gpio_driver.cpp
    startup/startup_stm32f411xe.s
    # Add your source files
)

target_link_options(${PROJECT_NAME} PRIVATE
    ${CPU_FLAGS}
    -T ${CMAKE_SOURCE_DIR}/STM32F411CEUx_FLASH.ld
    -Wl,--gc-sections
    -Wl,--print-memory-usage
    -specs=nano.specs       # Newlib-nano (smaller printf)
    -specs=nosys.specs
)

# Post-build: generate .bin and .hex
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND arm-none-eabi-objcopy -O binary $<TARGET_FILE:${PROJECT_NAME}> ${PROJECT_NAME}.bin
    COMMAND arm-none-eabi-objcopy -O ihex   $<TARGET_FILE:${PROJECT_NAME}> ${PROJECT_NAME}.hex
    COMMAND arm-none-eabi-size $<TARGET_FILE:${PROJECT_NAME}>
)
```

---

## Chapter 9: GPIO — Blink and Beyond

### 9.1 GPIO Theory (STM32)

Each GPIO port on STM32 has these key registers:

| Register | Purpose |
|---|---|
| `MODER` | Mode: Input / Output / AF / Analog (2 bits/pin) |
| `OTYPER` | Output type: Push-pull / Open-drain (1 bit/pin) |
| `OSPEEDR` | Speed: Low / Medium / Fast / High |
| `PUPDR` | Pull-up / Pull-down / Floating |
| `IDR` | Input Data Register (read-only) |
| `ODR` | Output Data Register |
| `BSRR` | Bit Set/Reset — **atomic** set and reset |
| `AFR[2]` | Alternate Function mapping |

### 9.2 C++ GPIO Driver for STM32

```cpp
// gpio_driver.hpp
#pragma once
#include "stm32f4xx.h"

enum class GpioMode   : uint8_t { Input=0, Output=1, AF=2, Analog=3 };
enum class GpioOType  : uint8_t { PushPull=0, OpenDrain=1 };
enum class GpioSpeed  : uint8_t { Low=0, Medium=1, Fast=2, High=3 };
enum class GpioPull   : uint8_t { None=0, PullUp=1, PullDown=2 };

class GpioPin {
public:
    GpioPin(GPIO_TypeDef* port, uint8_t pin,
            GpioMode mode, GpioOType otype = GpioOType::PushPull,
            GpioSpeed speed = GpioSpeed::Fast, GpioPull pull = GpioPull::None)
        : port_(port), pin_(pin)
    {
        // Enable GPIO clock via RCC (simplified)
        enableClock(port);

        uint32_t pos2 = pin_ * 2u;
        port_->MODER  = (port_->MODER  & ~(3u << pos2)) | (static_cast<uint32_t>(mode)  << pos2);
        port_->OSPEEDR= (port_->OSPEEDR& ~(3u << pos2)) | (static_cast<uint32_t>(speed) << pos2);
        port_->PUPDR  = (port_->PUPDR  & ~(3u << pos2)) | (static_cast<uint32_t>(pull)  << pos2);
        if (otype == GpioOType::OpenDrain)
            port_->OTYPER |= (1u << pin_);
    }

    // Atomic set/clear via BSRR (single-cycle, IRQ-safe)
    inline void set()    const { port_->BSRR = (1u << pin_); }
    inline void clear()  const { port_->BSRR = (1u << (pin_ + 16)); }
    inline void toggle() const { port_->ODR ^= (1u << pin_); }
    inline bool read()   const { return (port_->IDR >> pin_) & 1u; }

    void setAlternateFunc(uint8_t af_num) const {
        uint8_t reg = pin_ >> 3;
        uint8_t pos = (pin_ & 7u) * 4;
        port_->AFR[reg] = (port_->AFR[reg] & ~(0xFu << pos)) | (af_num << pos);
    }

private:
    GPIO_TypeDef* const port_;
    const uint8_t pin_;

    static void enableClock(GPIO_TypeDef* port) {
        if      (port == GPIOA) RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
        else if (port == GPIOB) RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
        else if (port == GPIOC) RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
        // Add other ports as needed
    }
};
```

### 9.3 Practice: Blink LED with Systick

```cpp
// main.cpp
#include "gpio_driver.hpp"

volatile uint32_t systick_ms = 0;

extern "C" void SysTick_Handler() {
    systick_ms++;
}

void delay_ms(uint32_t ms) {
    uint32_t start = systick_ms;
    while ((systick_ms - start) < ms);
}

int main() {
    SystemClock_Config();
    SysTick_Config(SystemCoreClock / 1000);  // 1 ms tick

    // STM32F411 Blackpill — LED on PC13
    GpioPin led(GPIOC, 13, GpioMode::Output, GpioOType::PushPull,
                GpioSpeed::Low, GpioPull::None);

    while (true) {
        led.toggle();
        delay_ms(500);
    }
}
```

### 9.4 Practice: Button Debounce

```cpp
class DebouncedButton {
public:
    DebouncedButton(GpioPin& pin, uint32_t debounce_ms = 20)
        : pin_(pin), debounce_ms_(debounce_ms) {}

    // Call this in main loop or timer ISR
    void update(uint32_t now_ms) {
        bool raw = !pin_.read();  // Active-low button
        if (raw != last_raw_) {
            last_edge_ms_ = now_ms;
            last_raw_ = raw;
        }
        if ((now_ms - last_edge_ms_) > debounce_ms_) {
            stable_state_ = raw;
        }
    }

    bool isPressed()  const { return stable_state_; }
    bool risingEdge() {
        bool r = stable_state_ && !prev_stable_;
        prev_stable_ = stable_state_;
        return r;
    }

private:
    GpioPin& pin_;
    uint32_t debounce_ms_, last_edge_ms_ = 0;
    bool last_raw_ = false, stable_state_ = false, prev_stable_ = false;
};
```

---

## Chapter 10: UART Communication

### 10.1 UART Theory

UART (Universal Asynchronous Receiver Transmitter) is the most fundamental serial interface.

```
Frame format: [START][D0][D1][D2][D3][D4][D5][D6][D7][PARITY?][STOP]
              idle=1    LSB first                              1 or 2 bits

Baud Rate: number of signal changes per second (bits/sec in UART)
BRR register = f_PCLK / baud_rate
```

### 10.2 STM32 UART Driver Class

```cpp
// uart_driver.hpp
#pragma once
#include "stm32f4xx.h"
#include "ring_buffer.hpp"

class UartDriver {
public:
    UartDriver(USART_TypeDef* uart, uint32_t baud,
               GpioPin& tx_pin, GpioPin& rx_pin, uint8_t af_num)
        : uart_(uart), baud_(baud)
    {
        // Configure TX/RX pins as AF
        tx_pin.setMode(GpioMode::AF);
        rx_pin.setMode(GpioMode::AF);
        tx_pin.setAlternateFunc(af_num);
        rx_pin.setAlternateFunc(af_num);

        // Enable USART clock
        enableClock();

        // Configure baud rate
        // For USART1/6 (APB2): f = 84 MHz
        // For USART2-5  (APB1): f = 42 MHz
        uint32_t apb_clk = getApbClock();
        uart_->BRR = apb_clk / baud;

        // Enable TX, RX, RXNE interrupt, USART
        uart_->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_RXNEIE | USART_CR1_UE;

        // Enable NVIC for this UART
        enableNVIC();
    }

    // Polling send (simple)
    void sendByte(uint8_t byte) {
        while (!(uart_->SR & USART_SR_TXE));
        uart_->DR = byte;
    }

    void sendString(const char* s) {
        while (*s) sendByte(*s++);
    }

    void send(const uint8_t* data, size_t len) {
        for (size_t i = 0; i < len; i++) sendByte(data[i]);
    }

    // Non-blocking receive via ring buffer
    bool readByte(uint8_t& byte) {
        return rx_buf_.pop(byte);
    }

    size_t available() const { return rx_buf_.size(); }

    // Called from ISR
    void handleIRQ() {
        if (uart_->SR & USART_SR_RXNE) {
            uint8_t b = uart_->DR;
            rx_buf_.push(b);
        }
    }

private:
    USART_TypeDef* const uart_;
    uint32_t baud_;
    RingBuffer<uint8_t, 256> rx_buf_;

    void enableClock() {
        if      (uart_ == USART1) RCC->APB2ENR |= RCC_APB2ENR_USART1EN;
        else if (uart_ == USART2) RCC->APB1ENR |= RCC_APB1ENR_USART2EN;
        else if (uart_ == USART6) RCC->APB2ENR |= RCC_APB2ENR_USART6EN;
    }

    uint32_t getApbClock() const {
        return (uart_ == USART1 || uart_ == USART6) ? 84000000UL : 42000000UL;
    }

    void enableNVIC() {
        IRQn_Type irqn = USART1_IRQn;  // Default; map per instance
        NVIC_SetPriority(irqn, 5);
        NVIC_EnableIRQ(irqn);
    }
};

// Singleton instances for ISR routing
extern UartDriver* g_uart1;

extern "C" void USART1_IRQHandler() {
    if (g_uart1) g_uart1->handleIRQ();
}
```

### 10.3 Practice: Printf Retargeting

```cpp
// retarget.cpp — redirect printf to UART
#include <cstdio>
extern UartDriver* g_uart1;

extern "C" int __io_putchar(int ch) {
    if (g_uart1) g_uart1->sendByte(static_cast<uint8_t>(ch));
    return ch;
}

// Usage
printf("Temp: %.2f C\r\n", temperature);
printf("Accel: %d %d %d\r\n", ax, ay, az);
```

---

## Chapter 11: Timers and PWM

### 11.1 STM32 Timer Architecture

STM32F4 has 14 timers. Key types:

- **Advanced (TIM1, TIM8):** PWM with dead-time, complementary outputs, break input
- **General Purpose (TIM2–5):** Most flexible, 32-bit, encoder mode, input capture
- **Basic (TIM6, TIM7):** Count only, good for DAC trigger and FreeRTOS tick
- **Low-Power (TIM9–14):** 16-bit, fewer channels

```
Timer clock → Prescaler (PSC) → Counter (CNT) → Auto-Reload (ARR)

f_counter = f_timer_clk / (PSC + 1)
f_overflow = f_counter / (ARR + 1)
Period_ms  = (ARR + 1) * (PSC + 1) / f_timer_clk * 1000
```

### 11.2 C++ PWM Driver

```cpp
class PwmChannel {
public:
    // timer: TIM2-5, channel: 1-4, freq_hz: desired PWM frequency
    PwmChannel(TIM_TypeDef* timer, uint8_t channel,
               uint32_t timer_clk_hz, uint32_t freq_hz)
        : timer_(timer), channel_(channel)
    {
        // Calculate PSC and ARR for desired frequency
        // ARR = (timer_clk / (PSC+1) / freq) - 1
        // Choose PSC to get ARR in 16-bit range
        uint32_t psc = (timer_clk_hz / (65535u * freq_hz));
        arr_ = (timer_clk_hz / ((psc + 1) * freq_hz)) - 1;

        timer_->PSC = psc;
        timer_->ARR = arr_;

        // Configure channel for PWM mode 1
        configureChannel();

        // Enable timer
        timer_->CR1 |= TIM_CR1_CEN;
    }

    // duty_pct: 0.0 to 100.0
    void setDuty(float duty_pct) {
        duty_pct = (duty_pct < 0.0f) ? 0.0f : (duty_pct > 100.0f) ? 100.0f : duty_pct;
        uint32_t ccr = static_cast<uint32_t>((duty_pct / 100.0f) * arr_);
        setCCR(ccr);
    }

    void setDutyRaw(uint32_t ccr) { setCCR(ccr); }
    uint32_t getARR() const { return arr_; }

private:
    TIM_TypeDef* const timer_;
    const uint8_t channel_;
    uint32_t arr_;

    void configureChannel() {
        // PWM Mode 1: OC active when CNT < CCR
        switch (channel_) {
        case 1:
            timer_->CCMR1 = (timer_->CCMR1 & ~TIM_CCMR1_OC1M) |
                             (6u << TIM_CCMR1_OC1M_Pos) |  // PWM mode 1
                             TIM_CCMR1_OC1PE;               // Preload enable
            timer_->CCER  |= TIM_CCER_CC1E;
            break;
        case 2:
            timer_->CCMR1 = (timer_->CCMR1 & ~TIM_CCMR1_OC2M) |
                             (6u << TIM_CCMR1_OC2M_Pos) | TIM_CCMR1_OC2PE;
            timer_->CCER  |= TIM_CCER_CC2E;
            break;
        // Cases 3, 4 use CCMR2...
        }
        timer_->EGR |= TIM_EGR_UG;  // Update generation
    }

    void setCCR(uint32_t val) {
        switch (channel_) {
        case 1: timer_->CCR1 = val; break;
        case 2: timer_->CCR2 = val; break;
        case 3: timer_->CCR3 = val; break;
        case 4: timer_->CCR4 = val; break;
        }
    }
};

// Practice: LED breathing effect
int main() {
    PwmChannel pwm(TIM3, 1, 84000000UL, 1000); // 1 kHz PWM on TIM3 CH1

    while (true) {
        // Fade in
        for (int i = 0; i <= 100; i++) {
            pwm.setDuty(static_cast<float>(i));
            delay_ms(10);
        }
        // Fade out
        for (int i = 100; i >= 0; i--) {
            pwm.setDuty(static_cast<float>(i));
            delay_ms(10);
        }
    }
}
```

---

## Chapter 12: I2C and SPI Peripherals

### 12.1 I2C Theory

I2C uses two wires (SDA + SCL) and allows multiple devices on one bus.

```
Bus transactions:
  Write: S | ADDR+W | ACK | REG | ACK | DATA... | P
  Read:  S | ADDR+W | ACK | REG | ACK | Sr | ADDR+R | ACK | DATA... | NACK | P
  S = START, Sr = Repeated START, P = STOP

Pull-up resistors required (typically 4.7kΩ for 100kHz, 2.2kΩ for 400kHz)
```

### 12.2 STM32 I2C Driver

```cpp
class I2cMaster {
public:
    I2cMaster(I2C_TypeDef* i2c, uint32_t clk_speed_hz) : i2c_(i2c) {
        // Enable I2C clock and GPIO (configure SCL/SDA as AF4 with open-drain)
        enableClock();

        i2c_->CR1 |= I2C_CR1_SWRST;    // Reset I2C peripheral
        i2c_->CR1 &= ~I2C_CR1_SWRST;

        // CR2: peripheral clock frequency in MHz (APB1 = 42 MHz)
        i2c_->CR2 = 42;

        // CCR: clock control register
        // For 400 kHz fast mode: CCR = f_PCLK1 / (3 * f_I2C)
        if (clk_speed_hz <= 100000) {
            i2c_->CCR = 42000000 / (2 * clk_speed_hz);  // Standard mode
        } else {
            i2c_->CCR = I2C_CCR_FS | (42000000 / (3 * clk_speed_hz)); // Fast
            i2c_->TRISE = 42 * 300 / 1000 + 1;  // 300ns rise time max
        }
        i2c_->TRISE = (clk_speed_hz <= 100000) ? 43 : 13;
        i2c_->CR1  |= I2C_CR1_PE;  // Enable I2C
    }

    // Write 'len' bytes to device_addr register reg_addr
    bool write(uint8_t dev_addr, uint8_t reg_addr,
               const uint8_t* data, size_t len) {
        if (!start()) return false;
        if (!sendAddr(dev_addr, false)) return false;  // Write mode
        if (!sendByte(reg_addr)) return false;
        for (size_t i = 0; i < len; i++) {
            if (!sendByte(data[i])) return false;
        }
        stop();
        return true;
    }

    bool writeReg(uint8_t dev_addr, uint8_t reg_addr, uint8_t val) {
        return write(dev_addr, reg_addr, &val, 1);
    }

    bool read(uint8_t dev_addr, uint8_t reg_addr, uint8_t* buf, size_t len) {
        // Write phase: send register address
        if (!start()) return false;
        if (!sendAddr(dev_addr, false)) return false;
        if (!sendByte(reg_addr)) return false;

        // Repeated start + read phase
        if (!start()) return false;
        if (!sendAddr(dev_addr, true)) return false;  // Read mode

        for (size_t i = 0; i < len; i++) {
            if (i == len - 1) {
                i2c_->CR1 &= ~I2C_CR1_ACK;  // NACK last byte
                stop();
            }
            uint32_t timeout = 10000;
            while (!(i2c_->SR1 & I2C_SR1_RXNE) && --timeout);
            buf[i] = i2c_->DR;
        }
        return true;
    }

private:
    I2C_TypeDef* const i2c_;

    bool start() {
        i2c_->CR1 |= I2C_CR1_ACK | I2C_CR1_START;
        uint32_t t = 10000;
        while (!(i2c_->SR1 & I2C_SR1_SB) && --t);
        return t > 0;
    }

    void stop() { i2c_->CR1 |= I2C_CR1_STOP; }

    bool sendAddr(uint8_t addr, bool read) {
        i2c_->DR = (addr << 1) | (read ? 1 : 0);
        uint32_t t = 10000;
        while (!(i2c_->SR1 & (read ? I2C_SR1_ADDR : I2C_SR1_ADDR)) && --t);
        (void)i2c_->SR2;  // Clear ADDR flag by reading SR2
        return t > 0;
    }

    bool sendByte(uint8_t byte) {
        uint32_t t = 10000;
        while (!(i2c_->SR1 & I2C_SR1_TXE) && --t);
        if (!t) return false;
        i2c_->DR = byte;
        return true;
    }

    void enableClock() {
        if      (i2c_ == I2C1) RCC->APB1ENR |= RCC_APB1ENR_I2C1EN;
        else if (i2c_ == I2C2) RCC->APB1ENR |= RCC_APB1ENR_I2C2EN;
        else if (i2c_ == I2C3) RCC->APB1ENR |= RCC_APB1ENR_I2C3EN;
    }
};

// Usage: Reading MPU-6050 on STM32
I2cMaster i2c(I2C1, 400000);
uint8_t who = 0;
i2c.read(0x68, 0x75, &who, 1);  // WHO_AM_I register
printf("MPU-6050 ID: 0x%02X\r\n", who);  // Should be 0x68
```

---

## Chapter 13: Interrupts and NVIC

### 13.1 NVIC Theory

```
NVIC Priority:
  - 4 bits of priority (0-15), where 0 = highest
  - Split into preemption priority and sub-priority via PRIGROUP
  - Lower number = higher priority (can preempt)
  - Equal preemption priority = no preemption (round-robin)

Priority grouping (AIRCR PRIGROUP field):
  PRIGROUP=4: 4 bits preempt, 0 bits sub (recommended for FreeRTOS)
```

### 13.2 EXTI (External Interrupt) Driver

```cpp
class ExtiInterrupt {
public:
    enum class Trigger : uint8_t { Rising=0, Falling=1, Both=2 };

    ExtiInterrupt(uint8_t pin, Trigger trig, uint8_t port_idx,
                  uint8_t priority, std::function<void()> callback)
        : pin_(pin), callback_(callback)
    {
        // Enable SYSCFG clock
        RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;

        // Select GPIO port for this EXTI line
        uint8_t reg_idx = pin / 4;
        uint8_t shift   = (pin % 4) * 4;
        SYSCFG->EXTICR[reg_idx] =
            (SYSCFG->EXTICR[reg_idx] & ~(0xFu << shift)) | (port_idx << shift);

        // Configure edge trigger
        if (trig == Trigger::Rising  || trig == Trigger::Both)
            EXTI->RTSR |= (1u << pin);
        if (trig == Trigger::Falling || trig == Trigger::Both)
            EXTI->FTSR |= (1u << pin);

        // Unmask and configure NVIC
        EXTI->IMR |= (1u << pin);
        IRQn_Type irqn = getIRQn(pin);
        NVIC_SetPriority(irqn, priority);
        NVIC_EnableIRQ(irqn);
    }

    void handleIRQ() {
        if (EXTI->PR & (1u << pin_)) {
            EXTI->PR = (1u << pin_);  // Clear pending bit (write 1 to clear)
            if (callback_) callback_();
        }
    }

private:
    uint8_t pin_;
    void (*callback_)();  // Simple function pointer (no std::function overhead)

    static IRQn_Type getIRQn(uint8_t pin) {
        if (pin == 0)         return EXTI0_IRQn;
        if (pin == 1)         return EXTI1_IRQn;
        if (pin == 2)         return EXTI2_IRQn;
        if (pin == 3)         return EXTI3_IRQn;
        if (pin == 4)         return EXTI4_IRQn;
        if (pin <= 9)         return EXTI9_5_IRQn;
        /* pin 10-15 */       return EXTI15_10_IRQn;
    }
};
```

---

## Chapter 14: DMA Transfers

### 14.1 DMA Theory

DMA (Direct Memory Access) moves data between peripherals and memory without CPU involvement.

```
Memory → Memory        (data copy)
Memory → Peripheral    (UART TX, SPI TX, DAC output)
Peripheral → Memory    (UART RX, ADC data, SPI RX)

DMA Stream configuration:
  Channel  → Selects which peripheral triggers the DMA
  Direction → M2P, P2M, M2M
  MSIZE/PSIZE → Data width (byte, halfword, word)
  MINC/PINC  → Auto-increment memory/peripheral address
  CIRC       → Circular mode (for streaming ADC, audio)
  Priority   → Low, Medium, High, Very High
```

### 14.2 UART DMA TX

```cpp
class UartDmaTx {
public:
    UartDmaTx(USART_TypeDef* uart, DMA_Stream_TypeDef* dma_stream,
              uint32_t dma_channel)
        : uart_(uart), dma_(dma_stream), channel_(dma_channel)
    {
        // Enable DMA2 clock (USART1 uses DMA2)
        RCC->AHB1ENR |= RCC_AHB1ENR_DMA2EN;

        // USART DMA request enable
        uart_->CR3 |= USART_CR3_DMAT;

        // Configure DMA stream (not enabled yet)
        dma_->CR = (channel_ << DMA_SxCR_CHSEL_Pos) |  // Channel select
                   DMA_SxCR_DIR_0    |                    // Mem → Periph
                   DMA_SxCR_MINC     |                    // Memory increment
                   DMA_SxCR_TCIE;                         // TC interrupt enable
        dma_->PAR = reinterpret_cast<uint32_t>(&uart_->DR); // Destination

        // Enable DMA2 stream7 IRQ (USART1 TX)
        NVIC_SetPriority(DMA2_Stream7_IRQn, 6);
        NVIC_EnableIRQ(DMA2_Stream7_IRQn);
    }

    // Non-blocking DMA transmit
    bool sendAsync(const uint8_t* data, size_t len) {
        if (busy_) return false;
        busy_ = true;

        dma_->CR  &= ~DMA_SxCR_EN;               // Disable to configure
        dma_->M0AR = reinterpret_cast<uint32_t>(data);
        dma_->NDTR = len;
        dma_->CR  |= DMA_SxCR_EN;                // Enable → transfer starts

        return true;
    }

    bool isBusy() const { return busy_; }

    void handleTC() {
        busy_ = false;
        // Clear DMA transfer complete flag in HISR/LISR
        DMA2->HIFCR |= DMA_HIFCR_CTCIF7;
    }

private:
    USART_TypeDef*     const uart_;
    DMA_Stream_TypeDef* const dma_;
    uint32_t channel_;
    volatile bool busy_ = false;
};
```

---

## Chapter 15: FreeRTOS on STM32 with C++

### 15.1 FreeRTOS Key Concepts

| Concept | Description |
|---|---|
| Task | Independent thread of execution with own stack |
| Queue | FIFO inter-task message passing |
| Semaphore | Signaling between tasks/ISRs |
| Mutex | Mutual exclusion with priority inheritance |
| Timer | Software timer for periodic/one-shot callbacks |
| Notification | Lightweight direct-to-task signaling |

### 15.2 C++ Task Wrapper

```cpp
// freertos_task.hpp — Base class for FreeRTOS tasks
#pragma once
#include "FreeRTOS.h"
#include "task.h"

class FreeRtosTask {
public:
    FreeRtosTask(const char* name, uint32_t stack_words, UBaseType_t priority)
        : name_(name), stack_words_(stack_words), priority_(priority) {}

    bool start() {
        return xTaskCreate(
            &FreeRtosTask::taskEntry,  // Static entry point
            name_,
            stack_words_,
            this,                      // Pass 'this' as pvParameters
            priority_,
            &handle_
        ) == pdPASS;
    }

    void suspend() { vTaskSuspend(handle_); }
    void resume()  { vTaskResume(handle_); }

    // Override this in derived class
    virtual void run() = 0;
    virtual ~FreeRtosTask() {}

protected:
    // Delay helpers
    void delayMs(uint32_t ms) { vTaskDelay(pdMS_TO_TICKS(ms)); }
    void delayUntil(TickType_t* prev_wake, uint32_t ms) {
        vTaskDelayUntil(prev_wake, pdMS_TO_TICKS(ms));
    }

private:
    const char*    name_;
    uint32_t       stack_words_;
    UBaseType_t    priority_;
    TaskHandle_t   handle_ = nullptr;

    static void taskEntry(void* pvParams) {
        auto* self = static_cast<FreeRtosTask*>(pvParams);
        self->run();
        vTaskDelete(nullptr);
    }
};
```

### 15.3 Complete FreeRTOS Application Example

```cpp
// Sensor task: reads IMU via I2C, posts to queue
class SensorTask : public FreeRtosTask {
public:
    SensorTask(I2cMaster& i2c, QueueHandle_t queue)
        : FreeRtosTask("Sensor", 512, 3), i2c_(i2c), queue_(queue) {}

    void run() override {
        uint8_t buf[6];
        TickType_t prev_wake = xTaskGetTickCount();

        while (true) {
            // Read accelerometer (MPU-6050 ACCEL_XOUT_H)
            if (i2c_.read(0x68, 0x3B, buf, 6)) {
                SensorData data;
                data.ax = static_cast<int16_t>((buf[0] << 8) | buf[1]);
                data.ay = static_cast<int16_t>((buf[2] << 8) | buf[3]);
                data.az = static_cast<int16_t>((buf[4] << 8) | buf[5]);

                xQueueSend(queue_, &data, 0);  // Non-blocking post
            }
            delayUntil(&prev_wake, 10);  // 100 Hz sample rate
        }
    }

private:
    I2cMaster& i2c_;
    QueueHandle_t queue_;
};

// Logger task: receives from queue, prints via UART
class LoggerTask : public FreeRtosTask {
public:
    LoggerTask(UartDriver& uart, QueueHandle_t queue)
        : FreeRtosTask("Logger", 256, 2), uart_(uart), queue_(queue) {}

    void run() override {
        SensorData data;
        while (true) {
            if (xQueueReceive(queue_, &data, portMAX_DELAY) == pdTRUE) {
                char buf[64];
                int n = snprintf(buf, sizeof(buf), "AX:%d AY:%d AZ:%d\r\n",
                                 data.ax, data.ay, data.az);
                uart_.send(reinterpret_cast<uint8_t*>(buf), n);
            }
        }
    }
private:
    UartDriver& uart_;
    QueueHandle_t queue_;
};

// main.cpp
int main() {
    SystemClock_Config();

    I2cMaster i2c(I2C1, 400000);
    UartDriver uart(USART1, 115200, tx_pin, rx_pin, 7);

    QueueHandle_t q = xQueueCreate(16, sizeof(SensorData));

    SensorTask sensor(i2c, q);
    LoggerTask  logger(uart, q);
    sensor.start();
    logger.start();

    vTaskStartScheduler();
    for (;;);  // Never reached
}
```

---

## Chapter 17: STM32 Practice Projects

### Project 1: Digital Thermometer (I2C + UART)
- Read temperature from an LM75/DS18B20 or internal ADC + NTC
- Display reading over UART at 1 Hz
- Implement high/low alert GPIOs

### Project 2: PWM Motor Speed Controller
- Read potentiometer via ADC (DMA circular mode)
- Map ADC value (0–4095) to PWM duty (0–100%)
- Display speed over UART
- Add direction control via GPIO

### Project 3: UART Command Shell
- Implement a small command interpreter over UART
- Commands: `led on`, `led off`, `gpio read PA5`, `temp`
- Use FreeRTOS queue for UART RX buffering

### Project 4: SPI Flash Logger
- Interface W25Q32 SPI NOR flash
- Implement read / write / erase sector functions
- Log sensor data with 4-byte timestamp header
- Read back and print log over UART

### Project 5: FreeRTOS Multi-Sensor Dashboard
- 3 tasks: ADC reader, IMU reader, UART logger
- Use FreeRTOS queues for inter-task communication
- Add a watchdog task that monitors task heartbeats
- Implement LED status indicator per task state

---

# PART 3 — ESP32 WITH C++

---

## Chapter 18: ESP32 Architecture Overview

### 18.1 ESP32 Silicon Family Comparison

| Feature | ESP32 | ESP32-S3 | ESP32-C3 | ESP32-H2 |
|---|---|---|---|---|
| Core | Xtensa LX6 (x2) | Xtensa LX7 (x2) | RISC-V (x1) | RISC-V (x1) |
| Max Clock | 240 MHz | 240 MHz | 160 MHz | 96 MHz |
| SRAM | 520 KB | 512 KB | 400 KB | 320 KB |
| Flash | External | External | External | External |
| WiFi | 802.11 b/g/n | b/g/n | b/g/n | — |
| Bluetooth | BT 4.2 + BLE | BLE 5.0 | BLE 5.0 | BLE 5.3 + 802.15.4 |
| AI Accel | — | Vector extension | — | — |
| USB | — | USB OTG 1.1 | — | — |
| Best For | General IoT | Wearables/AI | Low-cost BLE | Thread/Matter |

### 18.2 Memory Architecture

```
Internal SRAM:
  SRAM0 (192 KB): Instruction RAM (IRAM) — time-critical ISRs and code
  SRAM1 (128 KB): Data RAM (DRAM)
  SRAM2 (200 KB): Data RAM (DRAM)

External Flash (via SPI/QSPI):
  Code (.text), read-only data (.rodata) — executed in place (XIP)

RTC SRAM (8 KB):
  Survives deep sleep — store state across sleep cycles

Cache:
  32 KB instruction cache + 32 KB data cache (Xtensa LX6)
```

### 18.3 Dual-Core Architecture

```
Core 0 (PRO_CPU):
  - Runs FreeRTOS system tasks
  - WiFi/BLE stack (pinned here by default)
  - Handles driver ISRs

Core 1 (APP_CPU):
  - Runs app_main() and user tasks
  - Available for user application code
  - Lower-priority FreeRTOS idle task

Both cores share:
  - External flash and SRAM
  - All peripherals
  - FreeRTOS scheduler
```

---

## Chapter 19: Toolchain Setup (ESP-IDF + CMake)

### 19.1 ESP-IDF Installation

```bash
# Linux/macOS
git clone --recursive https://github.com/espressif/esp-idf.git ~/esp/esp-idf
cd ~/esp/esp-idf
./install.sh esp32s3      # Install for your target
source export.sh           # Set up environment

# Windows (use ESP-IDF Tools Installer)
```

### 19.2 Project Structure

```
my_project/
├── CMakeLists.txt          # Top-level CMake
├── sdkconfig               # Auto-generated from menuconfig
├── sdkconfig.defaults      # Your default config (commit this)
├── main/
│   ├── CMakeLists.txt
│   ├── main.cpp            # Entry point
│   └── Kconfig.projbuild   # Custom menuconfig items
├── components/
│   ├── uart_driver/
│   │   ├── CMakeLists.txt
│   │   ├── include/uart_driver.hpp
│   │   └── uart_driver.cpp
│   └── sensor/
│       └── ...
└── partitions.csv          # Custom partition table
```

### 19.3 Top-Level CMakeLists.txt

```cmake
# CMakeLists.txt (top-level)
cmake_minimum_required(VERSION 3.22)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(my_esp32_project)

# main/CMakeLists.txt
idf_component_register(
    SRCS "main.cpp"
    INCLUDE_DIRS "."
    REQUIRES
        driver
        nvs_flash
        esp_wifi
        bt
        esp_http_server
        littlefs
)
```

### 19.4 sdkconfig.defaults for C++

```ini
# sdkconfig.defaults — enables C++17 and configures system
CONFIG_COMPILER_CXX_EXCEPTIONS=n      # Disable exceptions (embedded style)
CONFIG_COMPILER_CXX_RTTI=n            # Disable RTTI
CONFIG_FREERTOS_UNICORE=n             # Enable dual-core
CONFIG_FREERTOS_HZ=1000               # 1 ms tick
CONFIG_ESP_MAIN_TASK_STACK_SIZE=8192  # Main task stack
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions.csv"
CONFIG_BOOTLOADER_LOG_LEVEL_WARN=y
```

---

## Chapter 20: GPIO and Basic I/O

### 20.1 ESP-IDF GPIO Driver

```cpp
// gpio_wrapper.hpp
#pragma once
#include "driver/gpio.h"

class EspGpioPin {
public:
    EspGpioPin(gpio_num_t pin, gpio_mode_t mode,
               gpio_pull_mode_t pull = GPIO_FLOATING)
        : pin_(pin)
    {
        gpio_config_t cfg = {};
        cfg.pin_bit_mask = 1ULL << pin;
        cfg.mode         = mode;
        cfg.pull_up_en   = (pull == GPIO_PULLUP_ONLY  || pull == GPIO_PULLUP_PULLDOWN)
                            ? GPIO_PULLUP_ENABLE : GPIO_PULLUP_DISABLE;
        cfg.pull_down_en = (pull == GPIO_PULLDOWN_ONLY || pull == GPIO_PULLUP_PULLDOWN)
                            ? GPIO_PULLDOWN_ENABLE : GPIO_PULLDOWN_DISABLE;
        cfg.intr_type    = GPIO_INTR_DISABLE;
        gpio_config(&cfg);
    }

    void set()    const { gpio_set_level(pin_, 1); }
    void clear()  const { gpio_set_level(pin_, 0); }
    void toggle() const { gpio_set_level(pin_, !gpio_get_level(pin_)); }
    bool read()   const { return gpio_get_level(pin_) != 0; }

    // Enable interrupt on this pin
    void enableInterrupt(gpio_int_type_t type, gpio_isr_t handler, void* arg) {
        gpio_set_intr_type(pin_, type);
        gpio_isr_handler_add(pin_, handler, arg);
    }

    gpio_num_t num() const { return pin_; }

private:
    gpio_num_t pin_;
};

// Usage
extern "C" void app_main() {
    EspGpioPin led(GPIO_NUM_2,  GPIO_MODE_OUTPUT);
    EspGpioPin btn(GPIO_NUM_0,  GPIO_MODE_INPUT, GPIO_PULLUP_ONLY);

    gpio_install_isr_service(0);  // Install global ISR service

    while (true) {
        if (!btn.read()) {      // Button pressed (active-low)
            led.toggle();
            vTaskDelay(pdMS_TO_TICKS(200));
        }
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
```

---

## Chapter 21: UART, I2C, and SPI

### 21.1 ESP32 UART Driver

```cpp
// esp32_uart.hpp
#pragma once
#include "driver/uart.h"

class Esp32Uart {
public:
    Esp32Uart(uart_port_t port, int baud, gpio_num_t tx, gpio_num_t rx,
              int rx_buf = 512, int tx_buf = 0)
        : port_(port)
    {
        uart_config_t cfg = {
            .baud_rate           = baud,
            .data_bits           = UART_DATA_8_BITS,
            .parity              = UART_PARITY_DISABLE,
            .stop_bits           = UART_STOP_BITS_1,
            .flow_ctrl           = UART_HW_FLOWCTRL_DISABLE,
            .rx_flow_ctrl_thresh = 0,
            .source_clk          = UART_SCLK_APB,
        };
        uart_driver_install(port_, rx_buf, tx_buf, 0, nullptr, 0);
        uart_param_config(port_, &cfg);
        uart_set_pin(port_, tx, rx, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    }

    ~Esp32Uart() { uart_driver_delete(port_); }

    int write(const uint8_t* data, size_t len) {
        return uart_write_bytes(port_, data, len);
    }

    int writeStr(const char* s) {
        return uart_write_bytes(port_, s, strlen(s));
    }

    int read(uint8_t* buf, size_t max_len, TickType_t timeout = pdMS_TO_TICKS(100)) {
        return uart_read_bytes(port_, buf, max_len, timeout);
    }

    void flush() { uart_flush(port_); }

private:
    uart_port_t port_;
};
```

### 21.2 ESP32 I2C Master

```cpp
#include "driver/i2c.h"

class Esp32I2cMaster {
public:
    Esp32I2cMaster(i2c_port_t port, gpio_num_t sda, gpio_num_t scl,
                   uint32_t clk_hz = 400000)
        : port_(port)
    {
        i2c_config_t cfg = {
            .mode             = I2C_MODE_MASTER,
            .sda_io_num       = sda,
            .scl_io_num       = scl,
            .sda_pullup_en    = GPIO_PULLUP_ENABLE,
            .scl_pullup_en    = GPIO_PULLUP_ENABLE,
            .master           = { .clk_speed = clk_hz },
            .clk_flags        = 0,
        };
        i2c_param_config(port_, &cfg);
        i2c_driver_install(port_, I2C_MODE_MASTER, 0, 0, 0);
    }

    ~Esp32I2cMaster() { i2c_driver_delete(port_); }

    esp_err_t writeReg(uint8_t dev_addr, uint8_t reg, uint8_t val,
                        TickType_t timeout = pdMS_TO_TICKS(10)) {
        i2c_cmd_handle_t cmd = i2c_cmd_link_create();
        i2c_master_start(cmd);
        i2c_master_write_byte(cmd, (dev_addr << 1) | I2C_MASTER_WRITE, true);
        i2c_master_write_byte(cmd, reg, true);
        i2c_master_write_byte(cmd, val, true);
        i2c_master_stop(cmd);
        esp_err_t ret = i2c_master_cmd_begin(port_, cmd, timeout);
        i2c_cmd_link_delete(cmd);
        return ret;
    }

    esp_err_t readRegs(uint8_t dev_addr, uint8_t reg, uint8_t* buf, size_t len,
                        TickType_t timeout = pdMS_TO_TICKS(10)) {
        i2c_cmd_handle_t cmd = i2c_cmd_link_create();
        i2c_master_start(cmd);
        i2c_master_write_byte(cmd, (dev_addr << 1) | I2C_MASTER_WRITE, true);
        i2c_master_write_byte(cmd, reg, true);
        i2c_master_start(cmd);                                                   // Repeated start
        i2c_master_write_byte(cmd, (dev_addr << 1) | I2C_MASTER_READ, true);
        if (len > 1) i2c_master_read(cmd, buf, len - 1, I2C_MASTER_ACK);
        i2c_master_read_byte(cmd, &buf[len - 1], I2C_MASTER_NACK);
        i2c_master_stop(cmd);
        esp_err_t ret = i2c_master_cmd_begin(port_, cmd, timeout);
        i2c_cmd_link_delete(cmd);
        return ret;
    }

private:
    i2c_port_t port_;
};

// Usage: GY-86 MPU-6050 accelerometer on ESP32-S3
extern "C" void app_main() {
    Esp32I2cMaster i2c(I2C_NUM_0, GPIO_NUM_21, GPIO_NUM_22, 400000);

    // Wake up MPU-6050 (clear sleep bit in PWR_MGMT_1)
    i2c.writeReg(0x68, 0x6B, 0x00);

    uint8_t buf[6];
    while (true) {
        i2c.readRegs(0x68, 0x3B, buf, 6);
        int16_t ax = (buf[0] << 8) | buf[1];
        int16_t ay = (buf[2] << 8) | buf[3];
        int16_t az = (buf[4] << 8) | buf[5];
        float ax_g = ax / 16384.0f;
        printf("Ax:%.3f Ay:%.3f Az:%.3f g\n", ax_g, ay/16384.0f, az/16384.0f);
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
```

---

## Chapter 22: FreeRTOS on ESP32 (Dual-Core)

### 22.1 Task Pinning

```cpp
// ESP32 FreeRTOS API for dual-core task pinning
// xTaskCreatePinnedToCore instead of xTaskCreate

class Esp32Task {
public:
    Esp32Task(const char* name, uint32_t stack, UBaseType_t prio,
              BaseType_t core)  // 0 = PRO_CPU, 1 = APP_CPU, tskNO_AFFINITY
        : name_(name), stack_(stack), prio_(prio), core_(core) {}

    bool start() {
        return xTaskCreatePinnedToCore(
            &Esp32Task::entry, name_, stack_, this, prio_, &handle_, core_
        ) == pdPASS;
    }

    virtual void run() = 0;
    virtual ~Esp32Task() {}

protected:
    void delayMs(uint32_t ms) { vTaskDelay(pdMS_TO_TICKS(ms)); }

private:
    const char* name_;
    uint32_t    stack_;
    UBaseType_t prio_;
    BaseType_t  core_;
    TaskHandle_t handle_ = nullptr;

    static void entry(void* p) {
        static_cast<Esp32Task*>(p)->run();
        vTaskDelete(nullptr);
    }
};

// BLE stack pinned to Core 0, sensor processing on Core 1
class BleTask : public Esp32Task {
public:
    BleTask() : Esp32Task("BLE", 8192, 5, 0) {}  // Core 0
    void run() override { /* BLE event loop */ }
};

class SensorTask : public Esp32Task {
public:
    SensorTask() : Esp32Task("Sensor", 4096, 4, 1) {}  // Core 1
    void run() override { /* IMU sampling + Kalman filter */ }
};
```

### 22.2 Inter-Core Communication

```cpp
// EventGroup: signal across cores
#include "freertos/event_groups.h"

EventGroupHandle_t g_events;

constexpr EventBits_t EVT_SENSOR_READY = BIT0;
constexpr EventBits_t EVT_BLE_CONNECTED = BIT1;
constexpr EventBits_t EVT_OTA_PENDING   = BIT2;

// Core 1 sensor task sets EVT_SENSOR_READY
void SensorTask::run() {
    while (true) {
        readAndProcessIMU();
        xEventGroupSetBits(g_events, EVT_SENSOR_READY);
        delayMs(10);
    }
}

// Core 0 BLE task waits for EVT_SENSOR_READY before notifying peer
void BleTask::run() {
    while (true) {
        // Wait for sensor data available, BLE connected, no OTA in progress
        EventBits_t bits = xEventGroupWaitBits(
            g_events,
            EVT_SENSOR_READY | EVT_BLE_CONNECTED,
            pdTRUE,       // Clear on exit
            pdTRUE,       // Wait for ALL bits
            pdMS_TO_TICKS(100)
        );
        if ((bits & (EVT_SENSOR_READY | EVT_BLE_CONNECTED)) ==
                    (EVT_SENSOR_READY | EVT_BLE_CONNECTED)) {
            sendBleNotification();
        }
    }
}
```

---

## Chapter 23: WiFi and TCP/IP Stack

### 23.1 WiFi Station Mode

```cpp
// wifi_manager.hpp
#pragma once
#include "esp_wifi.h"
#include "esp_event.h"
#include "nvs_flash.h"
#include "freertos/event_groups.h"

class WifiManager {
public:
    static constexpr EventBits_t CONNECTED_BIT    = BIT0;
    static constexpr EventBits_t DISCONNECTED_BIT = BIT1;

    WifiManager() {
        event_group_ = xEventGroupCreate();

        esp_netif_init();
        esp_event_loop_create_default();
        esp_netif_create_default_wifi_sta();

        wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
        esp_wifi_init(&cfg);

        esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                    &WifiManager::wifiEventHandler, this);
        esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                    &WifiManager::ipEventHandler, this);
    }

    void connect(const char* ssid, const char* password) {
        wifi_config_t wifi_cfg = {};
        strncpy(reinterpret_cast<char*>(wifi_cfg.sta.ssid),     ssid,     31);
        strncpy(reinterpret_cast<char*>(wifi_cfg.sta.password), password, 63);
        wifi_cfg.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;

        esp_wifi_set_mode(WIFI_MODE_STA);
        esp_wifi_set_config(WIFI_IF_STA, &wifi_cfg);
        esp_wifi_start();
    }

    // Block until connected or timeout
    bool waitConnected(uint32_t timeout_ms = 15000) {
        EventBits_t bits = xEventGroupWaitBits(
            event_group_, CONNECTED_BIT, pdFALSE, pdTRUE,
            pdMS_TO_TICKS(timeout_ms));
        return (bits & CONNECTED_BIT) != 0;
    }

    bool isConnected() const { return connected_; }

private:
    EventGroupHandle_t event_group_;
    bool connected_ = false;

    static void wifiEventHandler(void* arg, esp_event_base_t base,
                                  int32_t id, void* data) {
        auto* self = static_cast<WifiManager*>(arg);
        if (id == WIFI_EVENT_STA_DISCONNECTED) {
            self->connected_ = false;
            xEventGroupSetBits(self->event_group_, DISCONNECTED_BIT);
            esp_wifi_connect();  // Auto-reconnect
        }
    }

    static void ipEventHandler(void* arg, esp_event_base_t base,
                                int32_t id, void* data) {
        auto* self = static_cast<WifiManager*>(arg);
        if (id == IP_EVENT_STA_GOT_IP) {
            auto* evt = static_cast<ip_event_got_ip_t*>(data);
            self->connected_ = true;
            xEventGroupSetBits(self->event_group_, CONNECTED_BIT);
            printf("IP: " IPSTR "\n", IP2STR(&evt->ip_info.ip));
        }
    }
};
```

### 23.2 MQTT over WiFi

```cpp
#include "mqtt_client.h"

class MqttClient {
public:
    MqttClient(const char* broker_uri) {
        esp_mqtt_client_config_t cfg = {
            .broker = { .address = { .uri = broker_uri } }
        };
        client_ = esp_mqtt_client_init(&cfg);
        esp_mqtt_client_register_event(client_, ESP_EVENT_ANY_ID,
                                        &MqttClient::eventHandler, this);
        esp_mqtt_client_start(client_);
    }

    void publish(const char* topic, const char* payload, int qos = 0) {
        esp_mqtt_client_publish(client_, topic, payload, 0, qos, 0);
    }

    void subscribe(const char* topic, int qos = 0) {
        esp_mqtt_client_subscribe(client_, topic, qos);
    }

private:
    esp_mqtt_client_handle_t client_;

    static void eventHandler(void* arg, esp_event_base_t base,
                               int32_t id, void* data) {
        auto evt = static_cast<esp_mqtt_event_handle_t>(data);
        switch (id) {
        case MQTT_EVENT_CONNECTED:
            printf("MQTT connected\n");
            break;
        case MQTT_EVENT_DATA:
            printf("Topic: %.*s, Data: %.*s\n",
                   evt->topic_len, evt->topic,
                   evt->data_len, evt->data);
            break;
        }
    }
};

// Usage
extern "C" void app_main() {
    nvs_flash_init();
    WifiManager wifi;
    wifi.connect("MySSID", "MyPassword");
    wifi.waitConnected();

    MqttClient mqtt("mqtt://broker.hivemq.com");
    mqtt.subscribe("device/cmd");

    int count = 0;
    while (true) {
        char buf[32];
        snprintf(buf, sizeof(buf), "{\"count\":%d}", count++);
        mqtt.publish("device/sensor", buf, 1);  // QoS 1
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}
```

---

## Chapter 24: BLE GATT Server/Client

### 24.1 BLE Theory

```
BLE Architecture:
  PHY → LL → HCI → L2CAP → ATT → GATT → Profiles

GATT Hierarchy:
  Server (peripheral) contains:
    Services (UUID, e.g. 0x180D = Heart Rate)
      Characteristics (UUID, value, properties: read/write/notify/indicate)
        Descriptors (e.g. CCCD for enabling notifications)

ATT Roles:
  Client: Central device (phone) — reads/writes characteristics
  Server: Peripheral device (wearable) — holds the data
```

### 24.2 ESP32 BLE GATT Server (NimBLE)

```cpp
// ble_server.hpp — NimBLE-based GATT server
#pragma once
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

// Custom sensor service UUIDs
// Service:        6E400001-B5A3-F393-E0A9-E50E24DCCA9E
// TX Notify char: 6E400003-B5A3-F393-E0A9-E50E24DCCA9E (Nordic UART-like)

static const ble_uuid128_t SENSOR_SVC_UUID =
    BLE_UUID128_INIT(0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
                     0x93, 0xf3, 0xa3, 0xb5, 0x01, 0x00, 0x40, 0x6e);

static const ble_uuid128_t SENSOR_TX_UUID =
    BLE_UUID128_INIT(0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
                     0x93, 0xf3, 0xa3, 0xb5, 0x03, 0x00, 0x40, 0x6e);

class BleGattServer {
public:
    static BleGattServer& instance() {
        static BleGattServer inst;
        return inst;
    }

    void init(const char* device_name) {
        device_name_ = device_name;
        nimble_port_init();
        ble_hs_cfg.sync_cb  = &BleGattServer::onSync;
        ble_hs_cfg.reset_cb = &BleGattServer::onReset;
        ble_svc_gap_init();
        ble_svc_gatt_init();
        registerServices();
        nimble_port_freertos_init(&BleGattServer::hostTask);
    }

    // Send notification to connected central
    esp_err_t notify(const uint8_t* data, size_t len) {
        if (conn_handle_ == BLE_HS_CONN_HANDLE_NONE) return ESP_ERR_INVALID_STATE;

        struct os_mbuf* om = ble_hs_mbuf_from_flat(data, len);
        if (!om) return ESP_ERR_NO_MEM;

        int rc = ble_gattc_notify_custom(conn_handle_, tx_attr_handle_, om);
        return rc == 0 ? ESP_OK : ESP_FAIL;
    }

    bool isConnected() const { return conn_handle_ != BLE_HS_CONN_HANDLE_NONE; }

private:
    const char* device_name_ = "ESP32-Sensor";
    uint16_t conn_handle_    = BLE_HS_CONN_HANDLE_NONE;
    uint16_t tx_attr_handle_ = 0;

    void registerServices() {
        static ble_gatt_chr_def chars[] = {
            {
                .uuid       = &SENSOR_TX_UUID.u,
                .access_cb  = &BleGattServer::charAccess,
                .flags      = BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &instance().tx_attr_handle_,
            },
            { 0 }  // Terminator
        };

        static ble_gatt_svc_def svcs[] = {
            {
                .type            = BLE_GATT_SVC_TYPE_PRIMARY,
                .uuid            = &SENSOR_SVC_UUID.u,
                .characteristics = chars,
            },
            { 0 }  // Terminator
        };

        ble_gatts_count_cfg(svcs);
        ble_gatts_add_svcs(svcs);
    }

    static int charAccess(uint16_t conn_handle, uint16_t attr_handle,
                           ble_gatt_access_ctxt* ctxt, void* arg) {
        return 0;  // Notify-only characteristic
    }

    static void onSync() {
        ble_addr_t addr;
        ble_hs_id_infer_auto(0, &addr.type);

        uint8_t adv_data[] = {
            0x02, 0x01, 0x06,                // Flags: LE General Discoverable
            0x0B, 0x09, 'E','S','P','3','2','-','S','e','n','s',  // Complete Name
        };

        struct ble_gap_adv_params adv_params = {};
        adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
        adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;

        ble_gap_adv_set_data(adv_data, sizeof(adv_data));
        ble_gap_adv_start(addr.type, nullptr, BLE_HS_FOREVER,
                          &adv_params, &BleGattServer::gapEvent, nullptr);
    }

    static int gapEvent(ble_gap_event* event, void* arg) {
        switch (event->type) {
        case BLE_GAP_EVENT_CONNECT:
            if (event->connect.status == 0)
                instance().conn_handle_ = event->connect.conn_handle;
            break;
        case BLE_GAP_EVENT_DISCONNECT:
            instance().conn_handle_ = BLE_HS_CONN_HANDLE_NONE;
            onSync();  // Restart advertising
            break;
        }
        return 0;
    }

    static void onReset(int reason) {
        printf("BLE reset: %d\n", reason);
    }

    static void hostTask(void* param) {
        nimble_port_run();
        nimble_port_freertos_deinit();
    }
};
```

---

## Chapter 25: NVS and LittleFS Storage

### 25.1 NVS (Non-Volatile Storage)

NVS stores key-value pairs in flash. Ideal for configuration, calibration, and small state.

```cpp
// nvs_config.hpp
#pragma once
#include "nvs_flash.h"
#include "nvs.h"

class NvsConfig {
public:
    explicit NvsConfig(const char* ns) : ns_(ns) {}

    esp_err_t open() {
        return nvs_open(ns_, NVS_READWRITE, &handle_);
    }

    void close() { nvs_close(handle_); }

    esp_err_t setU32(const char* key, uint32_t val) {
        esp_err_t r = nvs_set_u32(handle_, key, val);
        if (r == ESP_OK) r = nvs_commit(handle_);
        return r;
    }

    esp_err_t getU32(const char* key, uint32_t& val, uint32_t def = 0) {
        esp_err_t r = nvs_get_u32(handle_, key, &val);
        if (r == ESP_ERR_NVS_NOT_FOUND) { val = def; return ESP_OK; }
        return r;
    }

    esp_err_t setBlob(const char* key, const void* data, size_t len) {
        esp_err_t r = nvs_set_blob(handle_, key, data, len);
        if (r == ESP_OK) r = nvs_commit(handle_);
        return r;
    }

    esp_err_t getBlob(const char* key, void* buf, size_t& len) {
        return nvs_get_blob(handle_, key, buf, &len);
    }

private:
    const char* ns_;
    nvs_handle_t handle_ = 0;
};

// Usage: store calibration offsets
struct CalData { float offset_x, offset_y, offset_z; };

void saveCalibration(const CalData& cal) {
    NvsConfig nvs("calibration");
    nvs.open();
    nvs.setBlob("imu_offsets", &cal, sizeof(cal));
    nvs.close();
}

CalData loadCalibration() {
    CalData cal = {0};
    NvsConfig nvs("calibration");
    nvs.open();
    size_t len = sizeof(cal);
    nvs.getBlob("imu_offsets", &cal, len);
    nvs.close();
    return cal;
}
```

### 25.2 LittleFS for File-Based Storage

```cpp
#include "esp_littlefs.h"
#include <stdio.h>

class LfsStorage {
public:
    explicit LfsStorage(const char* partition = "storage") {
        esp_vfs_littlefs_conf_t cfg = {
            .base_path              = "/lfs",
            .partition_label        = partition,
            .format_if_mount_failed = true,
            .dont_mount             = false,
        };
        esp_vfs_littlefs_register(&cfg);
    }

    ~LfsStorage() { esp_vfs_littlefs_unregister("storage"); }

    // Append binary data to a log file
    bool appendLog(const char* filename, const void* data, size_t len) {
        char path[64];
        snprintf(path, sizeof(path), "/lfs/%s", filename);
        FILE* f = fopen(path, "ab");
        if (!f) return false;
        size_t written = fwrite(data, 1, len, f);
        fclose(f);
        return written == len;
    }

    bool readFile(const char* filename, void* buf, size_t max, size_t& got) {
        char path[64];
        snprintf(path, sizeof(path), "/lfs/%s", filename);
        FILE* f = fopen(path, "rb");
        if (!f) return false;
        got = fread(buf, 1, max, f);
        fclose(f);
        return true;
    }

    size_t getFileSize(const char* filename) {
        char path[64];
        snprintf(path, sizeof(path), "/lfs/%s", filename);
        struct stat st;
        if (stat(path, &st) == 0) return st.st_size;
        return 0;
    }

    void deleteFile(const char* filename) {
        char path[64];
        snprintf(path, sizeof(path), "/lfs/%s", filename);
        remove(path);
    }
};
```

---

## Chapter 26: OTA Firmware Updates

### 26.1 ESP-IDF Native OTA

```cpp
#include "esp_ota_ops.h"
#include "esp_https_ota.h"
#include "esp_http_client.h"

class OtaUpdater {
public:
    enum class State { Idle, Downloading, Verifying, Rebooting, Failed };

    State performUpdate(const char* url) {
        state_ = State::Downloading;

        esp_http_client_config_t http_cfg = {
            .url             = url,
            .cert_pem        = server_cert_pem_,  // Pinned server cert
            .timeout_ms      = 5000,
            .keep_alive_enable = true,
        };

        esp_https_ota_config_t ota_cfg = {
            .http_config            = &http_cfg,
            .http_client_init_cb    = nullptr,
            .bulk_flash_erase       = false,
            .partial_http_download  = true,
            .max_http_request_size  = 4096,
        };

        esp_https_ota_handle_t handle = nullptr;
        esp_err_t err = esp_https_ota_begin(&ota_cfg, &handle);
        if (err != ESP_OK) { state_ = State::Failed; return state_; }

        while (true) {
            err = esp_https_ota_perform(handle);
            if (err == ESP_ERR_HTTPS_OTA_IN_PROGRESS) {
                int written = esp_https_ota_get_image_len_read(handle);
                printf("OTA progress: %d bytes\n", written);
                continue;
            }
            break;
        }

        if (err == ESP_OK && esp_https_ota_is_complete_data_received(handle)) {
            state_ = State::Verifying;
            err = esp_https_ota_finish(handle);
        }

        if (err == ESP_OK) {
            state_ = State::Rebooting;
            printf("OTA success. Rebooting...\n");
            vTaskDelay(pdMS_TO_TICKS(1000));
            esp_restart();
        } else {
            esp_https_ota_abort(handle);
            state_ = State::Failed;
        }

        return state_;
    }

    State getState() const { return state_; }

private:
    State state_ = State::Idle;
    static const char* server_cert_pem_;  // Embed cert via CMake EMBED_TXTFILES
};
```

### 26.2 Partition Table for OTA

```csv
# partitions.csv
# Name,    Type, SubType, Offset,  Size,    Flags
nvs,        data, nvs,     0x9000,  0x4000,
otadata,    data, ota,     0xd000,  0x2000,
phy_init,   data, phy,     0xf000,  0x1000,
ota_0,      app,  ota_0,   0x10000, 0x1E0000,
ota_1,      app,  ota_1,   0x1F0000,0x1E0000,
storage,    data, spiffs,  0x3D0000,0x30000,
```

---

## Chapter 27: Low-Power and Deep Sleep

### 27.1 ESP32 Power Modes

| Mode | Current | Wake Sources | Retention |
|---|---|---|---|
| Active | 240 mA | N/A | All |
| Modem Sleep | 20 mA | WiFi/BLE beacon | All |
| Light Sleep | 800 µA | Timer, GPIO, UART | RTC, ULP |
| Deep Sleep | 10–150 µA | Timer, GPIO, ULP | RTC SRAM/Reg |
| Hibernation | 5 µA | Timer, GPIO | RTC Reg only |

```cpp
#include "esp_sleep.h"
#include "esp_timer.h"

class DeepSleepManager {
public:
    // Struct stored in RTC SRAM — survives deep sleep
    struct RTC_DATA_ATTR PersistentState {
        uint32_t boot_count;
        float    last_temperature;
        uint8_t  alert_flags;
    };

    // Wake-up sources
    static void enableTimerWakeup(uint64_t sleep_us) {
        esp_sleep_enable_timer_wakeup(sleep_us);
    }

    static void enableGpioWakeup(gpio_num_t pin, int level) {
        // For deep sleep, only RTC-capable GPIOs work
        esp_sleep_enable_ext0_wakeup(pin, level);
    }

    static void enableMultiGpioWakeup(uint64_t pin_mask) {
        // Wake if any of the masked GPIO changes
        esp_sleep_enable_ext1_wakeup(pin_mask, ESP_EXT1_WAKEUP_ANY_HIGH);
    }

    static esp_sleep_wakeup_cause_t getWakeReason() {
        return esp_sleep_get_wakeup_cause();
    }

    // Enter deep sleep — CPU stops here, resumes at app_main on wake
    static void enterDeepSleep() {
        printf("Entering deep sleep...\n");
        esp_deep_sleep_start();
    }
};

// RTC-retained state (initialized once, persists across deep sleeps)
RTC_DATA_ATTR DeepSleepManager::PersistentState g_rtc_state;

extern "C" void app_main() {
    g_rtc_state.boot_count++;

    auto reason = DeepSleepManager::getWakeReason();
    switch (reason) {
    case ESP_SLEEP_WAKEUP_TIMER:
        printf("Woke from timer (boot #%lu)\n", g_rtc_state.boot_count);
        break;
    case ESP_SLEEP_WAKEUP_EXT0:
        printf("Woke from GPIO\n");
        break;
    default:
        printf("Power-on reset (boot #%lu)\n", g_rtc_state.boot_count);
        break;
    }

    // Do work: read sensor, send data over BLE, etc.
    doMeasurementAndTransmit();

    // Sleep for 30 seconds
    DeepSleepManager::enableTimerWakeup(30ULL * 1000 * 1000);  // 30s in µs
    DeepSleepManager::enterDeepSleep();
}
```

---

## Chapter 28: ESP32 Practice Projects

### Project 1: BLE Accelerometer Wearable
- Initialize IMU via I2C on Core 1
- Sample at 100 Hz, compute magnitude
- Run BLE GATT server on Core 0
- Notify connected phone with packet: `[timestamp(4)][ax(2)][ay(2)][az(2)]`
- Log raw packets to LittleFS

### Project 2: WiFi Sensor Dashboard
- Read temperature/humidity from DHT22 or SHT31
- Serve a simple HTTP dashboard (ESP-IDF http_server)
- POST data to an MQTT broker every 30 seconds
- Implement WiFi auto-reconnect with exponential backoff

### Project 3: OTA + NVS Configuration System
- HTTP OTA endpoint in app (check a URL for new firmware version)
- NVS-stored config: SSID, broker URL, sample interval
- JSON config endpoint: `POST /config` updates NVS and reboots
- Version info endpoint: `GET /info` returns build timestamp, git hash

### Project 4: Deep Sleep Datalogger
- Read sensor, timestamp with SNTP, append to LittleFS file
- Sleep 60 seconds between samples
- On button press (GPIO wakeup): enter active mode, WiFi connect, upload log
- Battery voltage monitoring via ADC with low-battery alarm

### Project 5: Dual-Core IMU Fusion + BLE
- Core 1: 200 Hz IMU sampling + Madgwick 9-DOF filter
- Core 0: BLE GATT notifications of quaternion data
- FreeRTOS double-buffer: Core 1 writes, Core 0 reads without lock
- NVS: store calibration offsets (gyro bias, accel scale)

---

# PART 4 — ADVANCED TOPICS

---

## Chapter 29: State Machines in C++

### 29.1 Enum-Based State Machine

```cpp
// Hierarchical State Machine for a BLE wearable device
enum class DeviceState : uint8_t {
    Booting,
    Idle,
    Advertising,
    Connected,
    Streaming,
    Logging,
    Fault,
    OtaUpdate,
    DeepSleep
};

enum class DeviceEvent : uint8_t {
    BootComplete,
    AdvertiseStart,
    BleConnect,
    BleDisconnect,
    StartStream,
    StopStream,
    StorageFull,
    FaultDetected,
    OtaAvailable,
    OtaComplete,
    SleepTimeout
};

class DeviceStateMachine {
public:
    DeviceState process(DeviceEvent event) {
        auto next = transition(state_, event);
        if (next != state_) {
            onExit(state_);
            state_ = next;
            onEnter(state_);
        }
        return state_;
    }

    DeviceState state() const { return state_; }

private:
    DeviceState state_ = DeviceState::Booting;

    DeviceState transition(DeviceState s, DeviceEvent e) {
        using S = DeviceState;
        using E = DeviceEvent;

        switch (s) {
        case S::Booting:
            if (e == E::BootComplete)   return S::Advertising;
            break;
        case S::Advertising:
            if (e == E::BleConnect)     return S::Connected;
            if (e == E::SleepTimeout)   return S::DeepSleep;
            break;
        case S::Connected:
            if (e == E::StartStream)    return S::Streaming;
            if (e == E::BleDisconnect)  return S::Advertising;
            if (e == E::OtaAvailable)   return S::OtaUpdate;
            break;
        case S::Streaming:
            if (e == E::StopStream)     return S::Connected;
            if (e == E::StorageFull)    return S::Logging;
            if (e == E::BleDisconnect)  return S::Advertising;
            break;
        case S::Fault:
            return S::Fault;  // Sticky fault — requires reboot
        default: break;
        }
        if (e == E::FaultDetected) return S::Fault;  // Global fault transition
        return s;  // No transition
    }

    void onEnter(DeviceState s) {
        switch (s) {
        case DeviceState::Advertising:
            bleServer.startAdvertising();
            ledTask.setPattern(LedPattern::Blink_1Hz);
            break;
        case DeviceState::Connected:
            ledTask.setPattern(LedPattern::Solid);
            break;
        case DeviceState::Streaming:
            sensorTask.start(SAMPLE_RATE_HZ);
            break;
        case DeviceState::DeepSleep:
            enterDeepSleep();
            break;
        case DeviceState::Fault:
            logFaultToNVS();
            ledTask.setPattern(LedPattern::FastBlink);
            break;
        default: break;
        }
    }

    void onExit(DeviceState s) {
        if (s == DeviceState::Streaming) sensorTask.stop();
    }
};
```

---

## Chapter 30: Ring Buffers and Lock-Free Structures

### 30.1 Lock-Free Single-Producer Single-Consumer Queue

```cpp
// SPSC ring buffer — safe between ONE producer and ONE consumer
// No mutex needed when used across two tasks or task + ISR
template<typename T, size_t N>
class SpscQueue {
    static_assert((N & (N-1)) == 0, "N must be power of 2");
    static constexpr size_t MASK = N - 1;

public:
    // Called by PRODUCER only
    bool push(const T& item) {
        size_t head = head_.load(std::memory_order_relaxed);
        size_t next = (head + 1) & MASK;
        if (next == tail_.load(std::memory_order_acquire)) {
            return false;  // Full
        }
        buf_[head] = item;
        head_.store(next, std::memory_order_release);
        return true;
    }

    // Called by CONSUMER only
    bool pop(T& item) {
        size_t tail = tail_.load(std::memory_order_relaxed);
        if (tail == head_.load(std::memory_order_acquire)) {
            return false;  // Empty
        }
        item = buf_[tail];
        tail_.store((tail + 1) & MASK, std::memory_order_release);
        return true;
    }

    bool empty() const {
        return head_.load(std::memory_order_acquire) ==
               tail_.load(std::memory_order_acquire);
    }

private:
    alignas(64) std::atomic<size_t> head_{0};  // Producer cache line
    alignas(64) std::atomic<size_t> tail_{0};  // Consumer cache line
    T buf_[N];
};

// ISR → Task communication without mutex
SpscQueue<SensorPacket, 64> imu_queue;

// ISR (producer): called at 200 Hz
extern "C" void TIM2_IRQHandler() {
    SensorPacket pkt;
    readIMU(pkt);
    imu_queue.push(pkt);  // Lock-free
}

// Task (consumer): processes packets
void SensorProcessTask::run() {
    SensorPacket pkt;
    while (true) {
        while (imu_queue.pop(pkt)) {
            runKalmanFilter(pkt);
        }
        delayMs(1);
    }
}
```

---

## Chapter 31: Unit Testing Embedded Code

### 31.1 Hardware Abstraction for Testability

```cpp
// Abstract interface — mockable
class IGpioPin {
public:
    virtual ~IGpioPin() = default;
    virtual void set()    = 0;
    virtual void clear()  = 0;
    virtual bool read() const = 0;
};

// Real implementation
class GpioPin : public IGpioPin { /* hardware code */ };

// Mock for unit tests
class MockGpioPin : public IGpioPin {
public:
    void set()   override { state_ = true;  calls_++; }
    void clear() override { state_ = false; calls_++; }
    bool read()  const override { return inject_state_; }

    int  callCount()  const { return calls_; }
    bool currentState() const { return state_; }
    void injectState(bool s) { inject_state_ = s; }

private:
    bool state_ = false, inject_state_ = false;
    int  calls_ = 0;
};

// Class under test uses interface
class LedBlinker {
public:
    LedBlinker(IGpioPin& led) : led_(led) {}
    void blink(int n) {
        for (int i = 0; i < n; i++) {
            led_.set(); delay(500);
            led_.clear(); delay(500);
        }
    }
private:
    IGpioPin& led_;
};

// Unit test (catch2 or Unity)
TEST_CASE("LedBlinker::blink calls LED correct number of times") {
    MockGpioPin mock;
    LedBlinker blinker(mock);
    blinker.blink(3);
    REQUIRE(mock.callCount() == 6);  // 3 set + 3 clear
    REQUIRE(!mock.currentState());    // Ends off
}
```

---

## Chapter 32: Production-Grade Fault Handling

### 32.1 Watchdog Timer

```cpp
// Software watchdog using FreeRTOS timer
class SoftwareWatchdog {
public:
    SoftwareWatchdog(const char* name, uint32_t timeout_ms,
                     void (*fault_cb)(const char*))
        : name_(name), timeout_ms_(timeout_ms), fault_cb_(fault_cb)
    {
        timer_ = xTimerCreate(name, pdMS_TO_TICKS(timeout_ms),
                               pdFALSE, this, &SoftwareWatchdog::timerCb);
        xTimerStart(timer_, 0);
    }

    // Task must call this periodically
    void kick() { xTimerReset(timer_, 0); }

private:
    const char* name_;
    uint32_t    timeout_ms_;
    void (*fault_cb_)(const char*);
    TimerHandle_t timer_;

    static void timerCb(TimerHandle_t h) {
        auto* self = static_cast<SoftwareWatchdog*>(pvTimerGetTimerID(h));
        self->fault_cb_(self->name_);
    }
};

// Hardware watchdog (IWDG on STM32)
class HardwareWatchdog {
public:
    // Timeout: 1ms to ~26s depending on prescaler
    HardwareWatchdog(uint32_t timeout_ms) {
        IWDG->KR  = 0x5555;  // Enable register access
        IWDG->PR  = 4;       // Prescaler /64 → 32 kHz/64 = 500 Hz
        IWDG->RLR = (timeout_ms * 500) / 1000;  // Reload value
        IWDG->KR  = 0xCCCC;  // Start watchdog
    }

    // MUST be called within timeout period
    void refresh() { IWDG->KR = 0xAAAA; }
};
```

### 32.2 Fault Handler and Hardfault Dump

```cpp
// Capture Cortex-M hardfault register state
struct HardfaultFrame {
    uint32_t r0, r1, r2, r3, r12;
    uint32_t lr;  // Link Register
    uint32_t pc;  // Faulting instruction
    uint32_t psr;
};

// Store in RTC SRAM (ESP32) or backup registers (STM32)
extern "C" void HardFault_Handler() {
    __asm volatile(
        "tst lr, #4        \n"
        "ite eq            \n"
        "mrseq r0, msp     \n"
        "mrsne r0, psp     \n"
        "b hard_fault_dump \n"
    );
}

extern "C" void hard_fault_dump(HardfaultFrame* frame) {
    // Log to UART (if still functional)
    printf("=== HARDFAULT ===\n");
    printf("PC:  0x%08lX\n", frame->pc);
    printf("LR:  0x%08lX\n", frame->lr);
    printf("PSR: 0x%08lX\n", frame->psr);
    printf("R0-R3: %08lX %08lX %08lX %08lX\n",
           frame->r0, frame->r1, frame->r2, frame->r3);

    // Log SCB fault status registers
    printf("CFSR: 0x%08lX\n", SCB->CFSR);   // Precise fault type
    printf("HFSR: 0x%08lX\n", SCB->HFSR);   // HardFault status
    printf("BFAR: 0x%08lX\n", SCB->BFAR);   // Bad memory address

    // Save fault record to backup registers / NVS
    saveFaultRecordToFlash(frame);

    // Reset system
    NVIC_SystemReset();
}
```

---

# APPENDIX

## Quick Reference: STM32 vs ESP32

| Attribute | STM32 (F4/L4/H7) | ESP32 / ESP32-S3 |
|---|---|---|
| Architecture | ARM Cortex-M4/M33/M7 | Xtensa LX6/LX7 |
| Cores | 1 | 2 |
| Typical RAM | 128–1024 KB | 520 KB + PSRAM option |
| Clock | 80–480 MHz | 240 MHz |
| Wireless | None (requires modem) | WiFi + BLE integrated |
| RTOS | FreeRTOS (add-on) | FreeRTOS (built-in IDF) |
| Primary SDK | HAL / LL / CubeMX | ESP-IDF |
| Debugger | ST-Link / J-Link | OpenOCD (JTAG/USB) |
| Flash Tool | STM32CubeProgrammer | esptool.py |
| Low Power | Stop2 / Shutdown (<2 µA) | Deep Sleep (10 µA) |
| Best For | Medical/Industrial bare-metal | Connected IoT wearables |

## Recommended Libraries

**STM32:**
- `STM32 HAL/LL` — Peripheral drivers
- `FreeRTOS` — RTOS
- `CMSIS-DSP` — Optimized DSP (FFT, filtering)
- `printf` (mpaland) — Small printf without malloc

**ESP32:**
- `ESP-IDF` — Full BSP
- `NimBLE` — Lightweight BLE (preferred over Bluedroid)
- `ESP-TLS` — mbedTLS wrapper
- `LVGL` — Embedded GUI (for display projects)
- `ArduinoJson` — JSON parsing (disable exceptions)

## Useful Compiler Flags Reference

```bash
# Common embedded C++ flags
-mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard  # STM32F4 FPU
-mcpu=cortex-m33+nodsp -mfpu=fpv5-sp-d16 -mfloat-abi=hard    # STM32L5/G4
-mlongcalls -mtext-section-literals                            # ESP32 Xtensa

-O2                     # Optimize for speed (production)
-Os                     # Optimize for size
-Og                     # Optimize for debugging

-fno-exceptions         # Disable C++ exceptions
-fno-rtti               # Disable run-time type info
-fno-use-cxa-atexit     # No global destructors
-ffunction-sections     # Each function in own section
-fdata-sections         # Each var in own section
-Wl,--gc-sections       # Linker: remove unused sections

-Wall -Wextra -Wpedantic # Enable all warnings
-Werror                  # Treat warnings as errors
-Wno-unused-parameter    # Allow unused params (common in callbacks)
```

---

*End of Course — Embedded C++ for STM32 and ESP32*

*Version 1.0 — Prepared for Embedded Firmware Engineering Curriculum*
