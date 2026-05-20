#include <stdint.h>

/* RCC Registers */
#define RCC_BASE        0x40023800
#define RCC_AHB1ENR     (*(volatile uint32_t *)(RCC_BASE + 0x30))
#define RCC_APB1ENR     (*(volatile uint32_t *)(RCC_BASE + 0x40))

/* GPIO Registers */
#define GPIOD_BASE      0x40020C00
#define GPIOD_MODER     (*(volatile uint32_t *)(GPIOD_BASE + 0x00))
#define GPIOD_AFRH      (*(volatile uint32_t *)(GPIOD_BASE + 0x24))

/* USART3 Registers (connected to ST-Link VCP) */
#define USART3_BASE     0x40004800
#define USART3_SR       (*(volatile uint32_t *)(USART3_BASE + 0x00))
#define USART3_DR       (*(volatile uint32_t *)(USART3_BASE + 0x04))
#define USART3_BRR      (*(volatile uint32_t *)(USART3_BASE + 0x08))
#define USART3_CR1      (*(volatile uint32_t *)(USART3_BASE + 0x0C))

/* USART Status Register bits */
#define USART_SR_TXE    (1 << 7)    /* Transmit data register empty */
#define USART_SR_RXNE   (1 << 5)    /* Read data register not empty */

/* USART Control Register bits */
#define USART_CR1_UE    (1 << 13)   /* USART enable */
#define USART_CR1_TE    (1 << 3)    /* Transmitter enable */
#define USART_CR1_RE    (1 << 2)    /* Receiver enable */

/**
 * Initialize USART3 for serial communication
 * PD8: USART3_TX (AF7)
 * PD9: USART3_RX (AF7)
 */
void uart_init(uint32_t baudrate) {
    /* Enable clocks */
    RCC_AHB1ENR |= (1 << 3);    /* GPIOD clock */
    RCC_APB1ENR |= (1 << 18);   /* USART3 clock */
    
    /* Configure PD8 (TX) and PD9 (RX) as alternate function */
    GPIOD_MODER &= ~((3 << 16) | (3 << 18));  /* Clear mode bits */
    GPIOD_MODER |= ((2 << 16) | (2 << 18));   /* Alternate function mode */
    
    /* Set alternate function 7 (USART3) for PD8 and PD9 */
    GPIOD_AFRH &= ~((0xF << 0) | (0xF << 4));  /* Clear AF bits */
    GPIOD_AFRH |= ((7 << 0) | (7 << 4));       /* AF7 */
    
    /* Configure USART3 */
    /* Baud rate = fck / (16 * USARTDIV) */
    /* For 16MHz APB1 clock and 115200 baud: USARTDIV = 16000000 / (16 * 115200) ≈ 8.68 */
    USART3_BRR = 16000000 / baudrate;
    
    /* Enable USART, transmitter, and receiver */
    USART3_CR1 = USART_CR1_UE | USART_CR1_TE | USART_CR1_RE;
}

/**
 * Send a single character via UART
 */
void uart_putc(char c) {
    /* Wait for transmit data register empty */
    while (!(USART3_SR & USART_SR_TXE));
    USART3_DR = c;
}

/**
 * Send a null-terminated string via UART
 */
void uart_puts(const char *str) {
    while (*str) {
        /* Convert \n to \r\n for proper terminal display */
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

/**
 * Receive a single character via UART
 */
char uart_getc(void) {
    /* Wait for data to be received */
    while (!(USART3_SR & USART_SR_RXNE));
    return USART3_DR;
}

/**
 * Send an integer as decimal string
 */
void uart_put_int(int32_t value) {
    char buffer[12];  /* Enough for -2147483648 */
    char *ptr = buffer + sizeof(buffer) - 1;
    uint32_t abs_value;
    int is_negative = 0;
    
    if (value < 0) {
        is_negative = 1;
        abs_value = -value;
    } else {
        abs_value = value;
    }
    
    *ptr = '\0';
    
    do {
        *(--ptr) = '0' + (abs_value % 10);
        abs_value /= 10;
    } while (abs_value > 0);
    
    if (is_negative) {
        *(--ptr) = '-';
    }
    
    uart_puts(ptr);
}

/**
 * Simple delay function
 */
static void delay(volatile uint32_t count) {
    while(count--) {
        __asm__("nop");
    }
}

/**
 * Main function - UART echo with counter
 */
int main(void) {
    uint32_t counter = 0;
    
    /* Initialize UART at 115200 baud */
    uart_init(115200);
    
    /* Send startup message */
    uart_puts("\n\r");
    uart_puts("========================================\n");
    uart_puts("STM32F429ZI UART Demo\n");
    uart_puts("========================================\n");
    uart_puts("Commands:\n");
    uart_puts("  h - Print this help\n");
    uart_puts("  c - Show counter\n");
    uart_puts("  r - Reset counter\n");
    uart_puts("  Any other key - Echo back\n");
    uart_puts("\n");
    
    while (1) {
        char c = uart_getc();  /* Wait for character */
        
        switch (c) {
            case 'h':
            case 'H':
                uart_puts("\nHelp:\n");
                uart_puts("  h - This help\n");
                uart_puts("  c - Show counter\n");
                uart_puts("  r - Reset counter\n");
                break;
                
            case 'c':
            case 'C':
                uart_puts("\nCounter: ");
                uart_put_int(counter);
                uart_puts("\n");
                break;
                
            case 'r':
            case 'R':
                counter = 0;
                uart_puts("\nCounter reset!\n");
                break;
                
            case '\r':  /* Enter key */
                uart_puts("\n");
                break;
                
            default:
                /* Echo the character */
                uart_putc(c);
                counter++;
                break;
        }
    }
    
    return 0;
}
