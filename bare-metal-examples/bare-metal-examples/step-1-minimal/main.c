#include <stdint.h>

/* STM32F429ZI Register Definitions */
#define RCC_BASE      0x40023800
#define RCC_AHB1ENR   (*(volatile uint32_t *)(RCC_BASE + 0x30))

#define GPIOB_BASE    0x40020400
#define GPIOB_MODER   (*(volatile uint32_t *)(GPIOB_BASE + 0x00))
#define GPIOB_ODR     (*(volatile uint32_t *)(GPIOB_BASE + 0x14))

#define LED_PIN       7    /* Green LED on PB7 (Nucleo-F429ZI) */

/**
 * Simple delay function
 * Note: This is a busy-wait delay, not accurate timing
 */
static void delay(volatile uint32_t count) {
    while(count--) {
        __asm__("nop");
    }
}

/**
 * Main function - Blinks LED on PB7
 */
int main(void) {
    /* Enable GPIOB clock */
    RCC_AHB1ENR |= (1 << 1);
    
    /* Configure PB7 as output (bits 14-15 in MODER) */
    GPIOB_MODER &= ~(3 << (LED_PIN * 2));  /* Clear mode bits */
    GPIOB_MODER |= (1 << (LED_PIN * 2));   /* Set as output (01) */
    
    /* Blink LED forever */
    while(1) {
        GPIOB_ODR ^= (1 << LED_PIN);  /* Toggle LED */
        delay(1000000);               /* Delay ~500ms at 16MHz */
    }
    
    return 0;
}
