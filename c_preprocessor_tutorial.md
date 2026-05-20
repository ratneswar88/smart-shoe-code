# C Preprocessor: Complete Guide for Embedded Systems

## Table of Contents
1. [Introduction](#introduction)
2. [File Inclusion](#file-inclusion)
3. [Macro Definitions](#macro-definitions)
4. [Conditional Compilation](#conditional-compilation)
5. [Predefined Macros](#predefined-macros)
6. [Advanced Techniques](#advanced-techniques)
7. [Best Practices](#best-practices)

---

## Introduction

The C preprocessor performs text manipulation **before** the compiler sees your code. All preprocessor directives start with `#` and don't require semicolons.

**Preprocessing Phases:**
```
Source Code (.c) 
    ↓
Preprocessor (#directives processed)
    ↓
Expanded Code (pure C)
    ↓
Compiler
    ↓
Object Code (.o)
```

---

## File Inclusion

### `#include` Directive

**Two Forms:**

```c
#include <stdio.h>      // System/Standard headers (searches system paths)
#include "myheader.h"   // User headers (searches current directory first)
```

**Practical Example - Hardware Abstraction:**

```c
// gpio_hal.h - Hardware Abstraction Layer
#ifndef GPIO_HAL_H
#define GPIO_HAL_H

#include <stdint.h>

// GPIO register definitions
#define GPIO_BASE_ADDR    0x40020000

typedef struct {
    volatile uint32_t MODER;    // Mode register
    volatile uint32_t OTYPER;   // Output type register
    volatile uint32_t OSPEEDR;  // Output speed register
    volatile uint32_t PUPDR;    // Pull-up/pull-down register
    volatile uint32_t IDR;      // Input data register
    volatile uint32_t ODR;      // Output data register
} GPIO_TypeDef;

#define GPIOA ((GPIO_TypeDef *)GPIO_BASE_ADDR)

#endif
```

**Including Multiple Files:**

```c
// main.c
#include <stdint.h>
#include <stdbool.h>
#include "gpio_hal.h"
#include "uart_driver.h"
#include "config.h"

int main(void) {
    // Your code here
}
```

---

## Macro Definitions

### Simple Macros (`#define`)

**Basic Constants:**

```c
#define LED_PIN           13
#define BUFFER_SIZE       256
#define UART_BAUD_RATE    115200
#define PI                3.14159265359
```

**Usage:**
```c
char rx_buffer[BUFFER_SIZE];  // Expands to: char rx_buffer[256];
```

### Function-like Macros

**Syntax:**
```c
#define MACRO_NAME(parameters) replacement_text
```

**Examples:**

```c
// Simple mathematical operations
#define SQUARE(x)       ((x) * (x))
#define MAX(a, b)       ((a) > (b) ? (a) : (b))
#define MIN(a, b)       ((a) < (b) ? (a) : (b))
#define ABS(x)          ((x) < 0 ? -(x) : (x))

// Register bit manipulation (crucial for embedded)
#define SET_BIT(reg, bit)       ((reg) |= (1U << (bit)))
#define CLEAR_BIT(reg, bit)     ((reg) &= ~(1U << (bit)))
#define TOGGLE_BIT(reg, bit)    ((reg) ^= (1U << (bit)))
#define READ_BIT(reg, bit)      (((reg) >> (bit)) & 1U)

// Multi-bit field operations
#define SET_BITS(reg, mask, value)   ((reg) = ((reg) & ~(mask)) | (value))
#define READ_BITS(reg, mask, pos)    (((reg) & (mask)) >> (pos))
```

**⚠️ CRITICAL: Always use parentheses!**

```c
// WRONG:
#define SQUARE(x) x * x

int result = SQUARE(2 + 3);  // Expands to: 2 + 3 * 2 + 3 = 11 (WRONG!)

// CORRECT:
#define SQUARE(x) ((x) * (x))

int result = SQUARE(2 + 3);  // Expands to: ((2 + 3) * (2 + 3)) = 25 (CORRECT!)
```

### Multi-line Macros

Use backslash `\` to continue to next line:

```c
#define GPIO_CONFIG(port, pin, mode) \
    do { \
        (port)->MODER &= ~(3U << ((pin) * 2)); \
        (port)->MODER |= ((mode) << ((pin) * 2)); \
    } while(0)

// Usage:
GPIO_CONFIG(GPIOA, 5, GPIO_MODE_OUTPUT);
```

**Why `do { ... } while(0)`?**
- Makes macro behave like a single statement
- Requires semicolon at the end
- Safe in all contexts (if/else, etc.)

```c
// Without do-while:
#define BAD_MACRO(x) \
    statement1; \
    statement2

if (condition)
    BAD_MACRO(5);  // Only statement1 is inside if!
else
    something();   // Compiler error!

// With do-while:
#define GOOD_MACRO(x) \
    do { \
        statement1; \
        statement2; \
    } while(0)

if (condition)
    GOOD_MACRO(5);  // Both statements inside if
else
    something();    // Works correctly!
```

### `#undef` - Undefine Macro

```c
#define TEMP_VALUE 100
// Use TEMP_VALUE
#undef TEMP_VALUE
// TEMP_VALUE is no longer defined

#define TEMP_VALUE 200  // Can redefine now
```

---

## Conditional Compilation

### `#ifdef` / `#ifndef` / `#endif`

**Header Guards (Essential!):**

```c
// my_module.h
#ifndef MY_MODULE_H    // If not defined
#define MY_MODULE_H    // Define it

// Header contents here
void my_function(void);

#endif  // End of guard
```

**Why Header Guards?**
- Prevents multiple inclusion
- Avoids redefinition errors

**Configuration-based Compilation:**

```c
// config.h
#define DEBUG_ENABLED
#define USE_UART
// #define USE_SPI    // Commented out, not used

// main.c
#ifdef DEBUG_ENABLED
    #include "debug_uart.h"
    #define DEBUG_PRINT(msg) uart_print(msg)
#else
    #define DEBUG_PRINT(msg)  // Compiles to nothing
#endif

#ifdef USE_UART
    #include "uart_driver.h"
#endif

#ifdef USE_SPI
    #include "spi_driver.h"
#endif
```

### `#if`, `#elif`, `#else`

**More Complex Conditions:**

```c
#define MCU_FAMILY_STM32   1
#define MCU_FAMILY_NRF52   2
#define MCU_FAMILY_ESP32   3

#define MCU_FAMILY MCU_FAMILY_STM32

#if MCU_FAMILY == MCU_FAMILY_STM32
    #include "stm32_hal.h"
    #define CLOCK_FREQ 84000000
#elif MCU_FAMILY == MCU_FAMILY_NRF52
    #include "nrf52_hal.h"
    #define CLOCK_FREQ 64000000
#elif MCU_FAMILY == MCU_FAMILY_ESP32
    #include "esp32_hal.h"
    #define CLOCK_FREQ 160000000
#else
    #error "Unknown MCU family!"
#endif
```

**Checking if Macro is Defined:**

```c
#if defined(DEBUG_MODE)
    // Debug code
#endif

// Equivalent to:
#ifdef DEBUG_MODE
    // Debug code
#endif

// Negation:
#if !defined(RELEASE_MODE)
    // Not release mode
#endif

// Multiple conditions:
#if defined(UART_ENABLED) && defined(DEBUG_MODE)
    #define DEBUG_UART_PRINT(msg) uart_send(msg)
#endif
```

### `#error` and `#warning`

**Compile-time Error Messages:**

```c
#ifndef BUFFER_SIZE
    #error "BUFFER_SIZE must be defined!"
#endif

#if BUFFER_SIZE < 64
    #error "BUFFER_SIZE must be at least 64 bytes"
#endif

#if CLOCK_FREQ > 200000000
    #warning "Clock frequency exceeds recommended maximum"
#endif
```

---

## Predefined Macros

**Standard Predefined Macros:**

```c
__FILE__        // Current source file name
__LINE__        // Current line number
__DATE__        // Compilation date (Mmm dd yyyy)
__TIME__        // Compilation time (hh:mm:ss)
__func__        // Current function name (C99)
__STDC__        // Defined as 1 for standard C compilers
```

**Practical Usage:**

```c
#include <stdio.h>

#define DEBUG_LOG(msg) \
    printf("[%s:%d] %s: %s\n", __FILE__, __LINE__, __func__, msg)

void initialize_sensor(void) {
    DEBUG_LOG("Initializing sensor");
    // Prints: [sensor.c:15] initialize_sensor: Initializing sensor
}

// Build information
const char *build_date = __DATE__;
const char *build_time = __TIME__;

void print_version(void) {
    printf("Built on %s at %s\n", __DATE__, __TIME__);
}
```

**Compiler-specific Macros:**

```c
// GCC
#ifdef __GNUC__
    #define COMPILER_VERSION (__GNUC__ * 10000 + __GNUC_MINOR__ * 100)
#endif

// ARM Compiler
#ifdef __arm__
    #define TARGET_ARM
#endif

// Architecture detection
#ifdef __x86_64__
    #define ARCH_64BIT
#else
    #define ARCH_32BIT
#endif
```

---

## Advanced Techniques

### Stringification (`#`)

Converts macro parameter to string:

```c
#define STRINGIFY(x) #x
#define TO_STRING(x) STRINGIFY(x)

#define VERSION_MAJOR 1
#define VERSION_MINOR 2
#define VERSION_PATCH 3

// Direct stringification
const char *version = TO_STRING(VERSION_MAJOR) "." 
                      TO_STRING(VERSION_MINOR) "." 
                      TO_STRING(VERSION_PATCH);
// Result: "1.2.3"

// Debug printing with variable names
#define PRINT_VAR(var) printf(#var " = %d\n", var)

int temperature = 25;
PRINT_VAR(temperature);  // Prints: temperature = 25
```

### Token Pasting (`##`)

Concatenates tokens:

```c
#define CONCAT(a, b) a##b
#define GPIO_PIN(port, num) GPIO##port##_PIN##num

// Usage:
int pin = GPIO_PIN(A, 5);  // Expands to: int pin = GPIOA_PIN5;

// Creating register access macros
#define REG(peripheral, reg) peripheral##_##reg

uint32_t val = REG(UART1, DR);  // Expands to: UART1_DR
```

**Generic GPIO Functions:**

```c
#define GPIO_INIT_FUNC(port) \
    void gpio_##port##_init(void) { \
        /* Initialize GPIO port */ \
    }

GPIO_INIT_FUNC(A)  // Creates: void gpio_A_init(void) { ... }
GPIO_INIT_FUNC(B)  // Creates: void gpio_B_init(void) { ... }
GPIO_INIT_FUNC(C)  // Creates: void gpio_C_init(void) { ... }
```

### Variadic Macros (C99)

Macros with variable number of arguments:

```c
// __VA_ARGS__ represents all variable arguments
#define DEBUG_PRINTF(format, ...) \
    printf("[DEBUG] " format "\n", ##__VA_ARGS__)

// Usage:
DEBUG_PRINTF("Starting system");              // No arguments
DEBUG_PRINTF("Temperature: %d", temp);        // One argument
DEBUG_PRINTF("X=%d, Y=%d", x, y);            // Multiple arguments

// Advanced logging with levels
#define LOG_ERROR(...)   log_message(LOG_LEVEL_ERROR, __VA_ARGS__)
#define LOG_WARNING(...) log_message(LOG_LEVEL_WARNING, __VA_ARGS__)
#define LOG_INFO(...)    log_message(LOG_LEVEL_INFO, __VA_ARGS__)

void log_message(int level, const char *format, ...) {
    // Implementation
}
```

### `#pragma` Directives

Compiler-specific directives:

```c
// Pack structures (remove padding)
#pragma pack(push, 1)
struct sensor_data {
    uint8_t id;
    uint32_t timestamp;
    uint16_t value;
};  // Total: 7 bytes (no padding)
#pragma pack(pop)

// Alignment
#pragma pack(4)  // Align to 4-byte boundaries

// Code section placement (embedded systems)
#pragma arm section code = "FAST_CODE"
void time_critical_function(void) {
    // This function will be placed in fast RAM
}
#pragma arm section code

// Compiler warnings
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-variable"
int unused_var;  // Warning suppressed
#pragma GCC diagnostic pop

// Optimize specific function
#pragma GCC optimize("O3")
void performance_critical_function(void) {
    // Optimized aggressively
}
```

---

## Best Practices for Embedded Systems

### 1. **Use Header Guards Everywhere**

```c
#ifndef MODULE_NAME_H
#define MODULE_NAME_H

// Header contents

#endif
```

### 2. **Meaningful Macro Names**

```c
// Good:
#define UART_BAUD_RATE_115200   115200
#define GPIO_MODE_OUTPUT        0x01
#define ADC_RESOLUTION_12BIT    12

// Bad:
#define BR  115200
#define M   0x01
#define R   12
```

### 3. **Type-Safe Macros vs Inline Functions**

```c
// Macro (type-unsafe, but works with any type)
#define MAX(a, b) ((a) > (b) ? (a) : (b))

// Better: Use inline function (type-safe)
static inline int max_int(int a, int b) {
    return (a > b) ? a : b;
}

// Or use _Generic (C11) for type-safe macros
#define MAX(a, b) _Generic((a), \
    int: max_int, \
    float: max_float, \
    double: max_double \
)(a, b)
```

### 4. **Configuration Files**

```c
// config.h - Centralized configuration
#ifndef CONFIG_H
#define CONFIG_H

// System configuration
#define SYSTEM_CLOCK_HZ     84000000UL
#define TICK_RATE_HZ        1000

// Feature enables
#define ENABLE_UART
#define ENABLE_I2C
// #define ENABLE_SPI  // Disabled

// Buffer sizes
#define UART_RX_BUFFER_SIZE  256
#define I2C_BUFFER_SIZE      128

// Debug settings
#ifdef DEBUG
    #define DEBUG_UART_ENABLED
    #define ASSERT_ENABLED
#endif

#endif
```

### 5. **Hardware Register Access**

```c
// Good practice: Create structured access
#define UART1_BASE    0x40011000

typedef struct {
    volatile uint32_t SR;   // Status register
    volatile uint32_t DR;   // Data register
    volatile uint32_t BRR;  // Baud rate register
    volatile uint32_t CR1;  // Control register 1
} UART_TypeDef;

#define UART1 ((UART_TypeDef *)UART1_BASE)

// Usage:
UART1->DR = data;
uint32_t status = UART1->SR;
```

### 6. **Conditional Debug Code**

```c
#ifdef DEBUG_MODE
    #define DEBUG_INIT()        debug_uart_init()
    #define DEBUG_PRINT(msg)    debug_uart_send(msg)
    #define DEBUG_VAR(var)      debug_print_var(#var, var)
    #define ASSERT(expr)        if(!(expr)) debug_assert_failed()
#else
    #define DEBUG_INIT()        ((void)0)
    #define DEBUG_PRINT(msg)    ((void)0)
    #define DEBUG_VAR(var)      ((void)0)
    #define ASSERT(expr)        ((void)0)
#endif

// Zero overhead when DEBUG_MODE is not defined!
```

### 7. **Bit Field Definitions**

```c
// Register bit definitions
#define UART_SR_TXE     (1U << 7)   // Transmit data register empty
#define UART_SR_TC      (1U << 6)   // Transmission complete
#define UART_SR_RXNE    (1U << 5)   // Read data register not empty

// Using bit fields
if (UART1->SR & UART_SR_TXE) {
    // Transmit buffer is empty
}

// Multi-bit fields
#define UART_CR1_M_Pos      12
#define UART_CR1_M_Msk      (1U << UART_CR1_M_Pos)
#define UART_CR1_M_8BIT     (0U << UART_CR1_M_Pos)
#define UART_CR1_M_9BIT     (1U << UART_CR1_M_Pos)
```

---

## Common Pitfalls and Solutions

### Pitfall 1: Missing Parentheses

```c
// WRONG:
#define MULTIPLY(x, y) x * y
int result = MULTIPLY(2 + 3, 4 + 5);  
// Expands to: 2 + 3 * 4 + 5 = 19 (WRONG!)

// CORRECT:
#define MULTIPLY(x, y) ((x) * (y))
int result = MULTIPLY(2 + 3, 4 + 5);  
// Expands to: ((2 + 3) * (4 + 5)) = 45 (CORRECT!)
```

### Pitfall 2: Side Effects in Macros

```c
#define SQUARE(x) ((x) * (x))

int a = 5;
int result = SQUARE(a++);  
// Expands to: ((a++) * (a++))
// a is incremented TWICE! Undefined behavior!

// Solution: Use inline function instead
static inline int square(int x) {
    return x * x;
}
int result = square(a++);  // a incremented only once
```

### Pitfall 3: Macro vs Function

```c
// Macro evaluates argument multiple times
#define MAX(a, b) ((a) > (b) ? (a) : (b))

int x = MAX(func1(), func2());  
// func1() and func2() may be called multiple times!

// Better: Use inline function
static inline int max(int a, int b) {
    return (a > b) ? a : b;
}
```

---

## Complete Example: Embedded Application

```c
// config.h
#ifndef CONFIG_H
#define CONFIG_H

#define MCU_STM32F4
#define SYSTEM_CLOCK    84000000UL

#define ENABLE_UART
#define ENABLE_LED_DEBUG

#ifdef ENABLE_LED_DEBUG
    #define LED_PIN     13
#endif

#endif

// gpio_macros.h
#ifndef GPIO_MACROS_H
#define GPIO_MACROS_H

#include <stdint.h>

#define GPIO_MODE_INPUT     0x00
#define GPIO_MODE_OUTPUT    0x01

#define SET_BIT(reg, bit)       ((reg) |= (1U << (bit)))
#define CLEAR_BIT(reg, bit)     ((reg) &= ~(1U << (bit)))
#define TOGGLE_BIT(reg, bit)    ((reg) ^= (1U << (bit)))
#define READ_BIT(reg, bit)      (((reg) >> (bit)) & 1U)

#endif

// main.c
#include "config.h"
#include "gpio_macros.h"

#ifdef ENABLE_LED_DEBUG
    #define LED_ON()    SET_BIT(GPIOA->ODR, LED_PIN)
    #define LED_OFF()   CLEAR_BIT(GPIOA->ODR, LED_PIN)
    #define LED_TOGGLE() TOGGLE_BIT(GPIOA->ODR, LED_PIN)
#else
    #define LED_ON()    ((void)0)
    #define LED_OFF()   ((void)0)
    #define LED_TOGGLE() ((void)0)
#endif

int main(void) {
    LED_ON();
    
    #ifdef ENABLE_UART
        uart_init();
    #endif
    
    while(1) {
        LED_TOGGLE();
        delay_ms(500);
    }
}
```

---

## Summary

**Key Takeaways:**

1. **File Inclusion**: Use `#include` for code reusability
2. **Macros**: Powerful but use with caution (parentheses!)
3. **Conditional Compilation**: Essential for multi-platform code
4. **Predefined Macros**: Useful for debugging and versioning
5. **Advanced Features**: Stringification, token pasting, variadic macros
6. **Best Practices**: Type safety, meaningful names, header guards

**When to Use:**
- ✅ Constants and bit definitions
- ✅ Hardware register access
- ✅ Conditional compilation
- ✅ Simple utilities (MAX, MIN, ABS)
- ❌ Complex logic (use functions instead)
- ❌ When side effects are involved

**Remember:** The preprocessor is a powerful tool for embedded systems, especially for hardware abstraction and configuration management. Use it wisely!
