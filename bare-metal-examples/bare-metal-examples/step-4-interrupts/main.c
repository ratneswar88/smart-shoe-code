#include <stdint.h>

/* RCC Registers */
#define RCC_BASE        0x40023800
#define RCC_AHB1ENR     (*(volatile uint32_t *)(RCC_BASE + 0x30))
#define RCC_APB1ENR     (*(volatile uint32_t *)(RCC_BASE + 0x40))

/* GPIO Registers */
#define GPIOB_BASE      0x40020400
#define GPIOB_MODER     (*(volatile uint32_t *)(GPIOB_BASE + 0x00))
#define GPIOB_ODR       (*(volatile uint32_t *)(GPIOB_BASE + 0x14))

#define GPIOD_BASE      0x40020C00
#define GPIOD_MODER     (*(volatile uint32_t *)(GPIOD_BASE + 0x00))
#define GPIOD_AFRH      (*(volatile uint32_t *)(GPIOD_BASE + 0x24))

/* USART3 Registers */
#define USART3_BASE     0x40004800
#define USART3_SR       (*(volatile uint32_t *)(USART3_BASE + 0x00))
#define USART3_DR       (*(volatile uint32_t *)(USART3_BASE + 0x04))
#define USART3_BRR      (*(volatile uint32_t *)(USART3_BASE + 0x08))
#define USART3_CR1      (*(volatile uint32_t *)(USART3_BASE + 0x0C))

/* SysTick Registers (part of Cortex-M4 core) */
#define SYSTICK_BASE    0xE000E010
#define SYST_CSR        (*(volatile uint32_t *)(SYSTICK_BASE + 0x00))
#define SYST_RVR        (*(volatile uint32_t *)(SYSTICK_BASE + 0x04))
#define SYST_CVR        (*(volatile uint32_t *)(SYSTICK_BASE + 0x08))

/* SysTick Control and Status Register bits */
#define SYSTICK_ENABLE      (1 << 0)    /* Enable counter */
#define SYSTICK_TICKINT     (1 << 1)    /* Enable interrupt */
#define SYSTICK_CLKSOURCE   (1 << 2)    /* Use processor clock */

#define LED_PIN         7    /* Green LED on PB7 */

/* Global variables */
volatile uint32_t systick_counter = 0;
volatile uint32_t led_toggle_counter = 0;

/**
 * SysTick Handler - Called every 1ms
 * This is defined in startup.s vector table
 */
void SysTick_Handler(void) {
    systick_counter++;
    
    /* Toggle LED every 500ms */
    if (systick_counter % 500 == 0) {
        GPIOB_ODR ^= (1 << LED_PIN);
        led_toggle_counter++;
    }
}

/**
 * Initialize SysTick timer for 1ms interrupts
 */
void systick_init(void) {
    /* 16MHz / 1000 = 16000 ticks per millisecond */
    SYST_RVR = 16000 - 1;  /* Reload value (count down from this) */
    SYST_CVR = 0;          /* Clear current value */
    
    /* Enable SysTick with interrupt and processor clock */
    SYST_CSR = SYSTICK_ENABLE | SYSTICK_TICKINT | SYSTICK_CLKSOURCE;
}

/**
 * Initialize GPIO for LED
 */
void led_init(void) {
    /* Enable GPIOB clock */
    RCC_AHB1ENR |= (1 << 1);
    
    /* Configure PB7 as output */
    GPIOB_MODER &= ~(3 << (LED_PIN * 2));
    GPIOB_MODER |= (1 << (LED_PIN * 2));
}

/**
 * Initialize USART3
 */
void uart_init(uint32_t baudrate) {
    /* Enable clocks */
    RCC_AHB1ENR |= (1 << 3);    /* GPIOD clock */
    RCC_APB1ENR |= (1 << 18);   /* USART3 clock */
    
    /* Configure GPIO pins */
    GPIOD_MODER &= ~((3 << 16) | (3 << 18));
    GPIOD_MODER |= ((2 << 16) | (2 << 18));
    GPIOD_AFRH &= ~((0xF << 0) | (0xF << 4));
    GPIOD_AFRH |= ((7 << 0) | (7 << 4));
    
    /* Configure USART */
    USART3_BRR = 16000000 / baudrate;
    USART3_CR1 = (1 << 13) | (1 << 3) | (1 << 2);
}

void uart_putc(char c) {
    while (!(USART3_SR & (1 << 7)));
    USART3_DR = c;
}

void uart_puts(const char *str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

void uart_put_int(uint32_t value) {
    char buffer[12];
    char *ptr = buffer + sizeof(buffer) - 1;
    
    *ptr = '\0';
    
    if (value == 0) {
        *(--ptr) = '0';
    } else {
        while (value > 0) {
            *(--ptr) = '0' + (value % 10);
            value /= 10;
        }
    }
    
    uart_puts(ptr);
}

/**
 * Non-blocking delay using SysTick counter
 */
void delay_ms(uint32_t ms) {
    uint32_t start = systick_counter;
    while ((systick_counter - start) < ms) {
        /* Wait - could put CPU to sleep here */
        __asm__("nop");
    }
}

/**
 * Main function - Demonstrates interrupt-driven timing
 */
int main(void) {
    uint32_t last_report_time = 0;
    
    /* Initialize peripherals */
    led_init();
    uart_init(115200);
    systick_init();  /* Start 1ms interrupts */
    
    /* Send startup message */
    uart_puts("\n\r");
    uart_puts("========================================\n");
    uart_puts("STM32F429ZI Interrupt Demo\n");
    uart_puts("========================================\n");
    uart_puts("SysTick: 1ms interrupts\n");
    uart_puts("LED: Toggles every 500ms in ISR\n");
    uart_puts("Main loop: Reports every 5 seconds\n");
    uart_puts("\n");
    
    while (1) {
        /* Check if 5 seconds elapsed */
        if ((systick_counter - last_report_time) >= 5000) {
            last_report_time = systick_counter;
            
            /* Report status */
            uart_puts("Status: ");
            uart_put_int(systick_counter / 1000);
            uart_puts("s elapsed, LED toggled ");
            uart_put_int(led_toggle_counter);
            uart_puts(" times\n");
        }
        
        /* Main loop is free to do other work */
        /* In a real application, this is where you'd handle tasks */
        
        /* Optional: Enter low-power mode until next interrupt */
        // __asm__("wfi");  /* Wait For Interrupt */
    }
    
    return 0;
}
