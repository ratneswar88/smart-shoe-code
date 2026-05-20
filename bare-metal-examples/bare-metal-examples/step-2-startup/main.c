#include <stdint.h>

/* STM32F429ZI Register Definitions */
#define RCC_BASE      0x40023800
#define RCC_AHB1ENR   (*(volatile uint32_t *)(RCC_BASE + 0x30))

#define GPIOB_BASE    0x40020400
#define GPIOB_MODER   (*(volatile uint32_t *)(GPIOB_BASE + 0x00))
#define GPIOB_ODR     (*(volatile uint32_t *)(GPIOB_BASE + 0x14))

#define LED_PIN       7

/* Global variables to demonstrate .data and .bss sections */

/* Initialized data - goes to .data section */
uint32_t blink_count = 0;              /* Will be copied from Flash to RAM */
const uint32_t delay_value = 1000000;  /* Stored in Flash (.rodata) */

/* Uninitialized data - goes to .bss section */
uint32_t led_state;                    /* Will be zeroed at startup */
uint32_t toggle_buffer[10];            /* Array in .bss, zeroed at startup */

/* String constant - stored in Flash */
const char startup_message[] = "System started\n";

/**
 * Delay function
 */
static void delay(volatile uint32_t count) {
    while(count--) {
        __asm__("nop");
    }
}

/**
 * Initialize LED GPIO
 */
void led_init(void) {
    /* Enable GPIOB clock */
    RCC_AHB1ENR |= (1 << 1);
    
    /* Configure PB7 as output */
    GPIOB_MODER &= ~(3 << (LED_PIN * 2));
    GPIOB_MODER |= (1 << (LED_PIN * 2));
    
    /* Initial LED state is OFF */
    led_state = 0;
    GPIOB_ODR &= ~(1 << LED_PIN);
}

/**
 * Toggle LED and record state
 */
void led_toggle(void) {
    GPIOB_ODR ^= (1 << LED_PIN);
    led_state = (GPIOB_ODR >> LED_PIN) & 1;
    
    /* Record toggle in circular buffer */
    toggle_buffer[blink_count % 10] = led_state;
    blink_count++;
}

/**
 * Main function demonstrating proper startup
 * 
 * This example shows:
 * 1. .data section: initialized globals (blink_count)
 * 2. .bss section: uninitialized globals (led_state, toggle_buffer)
 * 3. .rodata section: constants (delay_value, startup_message)
 * 
 * The startup code (startup_full.s) handles:
 * - Copying .data from Flash to RAM
 * - Zeroing .bss section
 * - Setting up stack
 * - Calling main()
 */
int main(void) {
    /* Initialize LED */
    led_init();
    
    /* Verify .bss was zeroed properly */
    /* led_state should be 0, all toggle_buffer entries should be 0 */
    
    /* Main loop */
    while(1) {
        led_toggle();
        delay(delay_value);
        
        /* Every 20 toggles, do something special */
        if (blink_count % 20 == 0) {
            /* Could send status, adjust timing, etc. */
            /* This demonstrates using the initialized data */
        }
    }
    
    return 0;
}

/**
 * Hard Fault Handler - useful for debugging
 * 
 * When a hard fault occurs, this handler is called.
 * It's a good place to set a breakpoint during development.
 */
void HardFault_Handler(void) {
    /* Disable interrupts */
    __asm__("cpsid i");
    
    /* Store fault information for debugging */
    volatile uint32_t *cfsr = (volatile uint32_t *)0xE000ED28;  /* Configurable Fault Status Register */
    volatile uint32_t *hfsr = (volatile uint32_t *)0xE000ED2C;  /* Hard Fault Status Register */
    volatile uint32_t *dfsr = (volatile uint32_t *)0xE000ED30;  /* Debug Fault Status Register */
    volatile uint32_t *afsr = (volatile uint32_t *)0xE000ED3C;  /* Auxiliary Fault Status Register */
    volatile uint32_t *bfar = (volatile uint32_t *)0xE000ED38;  /* Bus Fault Address Register */
    volatile uint32_t *mmar = (volatile uint32_t *)0xE000ED34;  /* MemManage Fault Address Register */
    
    /* Read fault status registers */
    volatile uint32_t cfsr_val = *cfsr;
    volatile uint32_t hfsr_val = *hfsr;
    volatile uint32_t dfsr_val = *dfsr;
    volatile uint32_t afsr_val = *afsr;
    volatile uint32_t bfar_val = *bfar;
    volatile uint32_t mmar_val = *mmar;
    
    /* Prevent compiler from optimizing away the reads */
    (void)cfsr_val;
    (void)hfsr_val;
    (void)dfsr_val;
    (void)afsr_val;
    (void)bfar_val;
    (void)mmar_val;
    
    /* Infinite loop - set breakpoint here to catch faults */
    while(1) {
        __asm__("nop");
    }
}
