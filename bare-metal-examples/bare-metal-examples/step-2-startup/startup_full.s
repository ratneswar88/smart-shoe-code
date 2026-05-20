.syntax unified
.cpu cortex-m4
.thumb

.global Reset_Handler
.global Default_Handler

/* Vector Table */
.section .vector_table,"a",%progbits
.type vector_table, %object
vector_table:
    .word _estack                    /* 0x00: Initial Stack Pointer */
    .word Reset_Handler              /* 0x04: Reset Handler */
    .word NMI_Handler                /* 0x08: NMI Handler */
    .word HardFault_Handler          /* 0x0C: Hard Fault Handler */
    .word MemManage_Handler          /* 0x10: MPU Fault Handler */
    .word BusFault_Handler           /* 0x14: Bus Fault Handler */
    .word UsageFault_Handler         /* 0x18: Usage Fault Handler */
    .word 0                          /* 0x1C: Reserved */
    .word 0                          /* 0x20: Reserved */
    .word 0                          /* 0x24: Reserved */
    .word 0                          /* 0x28: Reserved */
    .word SVC_Handler                /* 0x2C: SVCall Handler */
    .word DebugMon_Handler           /* 0x30: Debug Monitor Handler */
    .word 0                          /* 0x34: Reserved */
    .word PendSV_Handler             /* 0x38: PendSV Handler */
    .word SysTick_Handler            /* 0x3C: SysTick Handler */

    /* External Interrupts - STM32F429 specific */
    .word WWDG_IRQHandler            /* 0x40: Window WatchDog */
    .word PVD_IRQHandler             /* 0x44: PVD through EXTI Line detection */
    .word TAMP_STAMP_IRQHandler      /* 0x48: Tamper and TimeStamps through the EXTI line */
    .word RTC_WKUP_IRQHandler        /* 0x4C: RTC Wakeup through the EXTI line */
    .word FLASH_IRQHandler           /* 0x50: FLASH */
    .word RCC_IRQHandler             /* 0x54: RCC */
    .word EXTI0_IRQHandler           /* 0x58: EXTI Line0 */
    .word EXTI1_IRQHandler           /* 0x5C: EXTI Line1 */
    .word EXTI2_IRQHandler           /* 0x60: EXTI Line2 */
    .word EXTI3_IRQHandler           /* 0x64: EXTI Line3 */
    .word EXTI4_IRQHandler           /* 0x68: EXTI Line4 */
    .word DMA1_Stream0_IRQHandler    /* 0x6C: DMA1 Stream 0 */
    .word DMA1_Stream1_IRQHandler    /* 0x70: DMA1 Stream 1 */
    .word DMA1_Stream2_IRQHandler    /* 0x74: DMA1 Stream 2 */
    .word DMA1_Stream3_IRQHandler    /* 0x78: DMA1 Stream 3 */
    .word DMA1_Stream4_IRQHandler    /* 0x7C: DMA1 Stream 4 */
    .word DMA1_Stream5_IRQHandler    /* 0x80: DMA1 Stream 5 */
    .word DMA1_Stream6_IRQHandler    /* 0x84: DMA1 Stream 6 */
    /* ... Add remaining 66 IRQ handlers ... */
    
.size vector_table, .-vector_table

/* Default handler implementations - weak aliases allow override in C */
.weak NMI_Handler
.weak HardFault_Handler
.weak MemManage_Handler
.weak BusFault_Handler
.weak UsageFault_Handler
.weak SVC_Handler
.weak DebugMon_Handler
.weak PendSV_Handler
.weak SysTick_Handler

.weak WWDG_IRQHandler
.weak PVD_IRQHandler
.weak TAMP_STAMP_IRQHandler
.weak RTC_WKUP_IRQHandler
.weak FLASH_IRQHandler
.weak RCC_IRQHandler
.weak EXTI0_IRQHandler
.weak EXTI1_IRQHandler
.weak EXTI2_IRQHandler
.weak EXTI3_IRQHandler
.weak EXTI4_IRQHandler
.weak DMA1_Stream0_IRQHandler
.weak DMA1_Stream1_IRQHandler
.weak DMA1_Stream2_IRQHandler
.weak DMA1_Stream3_IRQHandler
.weak DMA1_Stream4_IRQHandler
.weak DMA1_Stream5_IRQHandler
.weak DMA1_Stream6_IRQHandler

/* Default handler implementation - infinite loop */
.section .text.Default_Handler,"ax",%progbits
.thumb_func
Default_Handler:
Infinite_Loop:
    b Infinite_Loop
.size Default_Handler, .-Default_Handler

/* All handlers alias to Default_Handler unless overridden */
NMI_Handler:
HardFault_Handler:
MemManage_Handler:
BusFault_Handler:
UsageFault_Handler:
SVC_Handler:
DebugMon_Handler:
PendSV_Handler:
SysTick_Handler:
WWDG_IRQHandler:
PVD_IRQHandler:
TAMP_STAMP_IRQHandler:
RTC_WKUP_IRQHandler:
FLASH_IRQHandler:
RCC_IRQHandler:
EXTI0_IRQHandler:
EXTI1_IRQHandler:
EXTI2_IRQHandler:
EXTI3_IRQHandler:
EXTI4_IRQHandler:
DMA1_Stream0_IRQHandler:
DMA1_Stream1_IRQHandler:
DMA1_Stream2_IRQHandler:
DMA1_Stream3_IRQHandler:
DMA1_Stream4_IRQHandler:
DMA1_Stream5_IRQHandler:
DMA1_Stream6_IRQHandler:
    b Default_Handler

/* Reset Handler - called on system reset */
.section .text.Reset_Handler
.weak Reset_Handler
.type Reset_Handler, %function
Reset_Handler:
    /* Copy .data section from flash to SRAM */
    ldr r0, =_sdata          /* Destination start address in SRAM */
    ldr r1, =_edata          /* Destination end address */
    ldr r2, =_sidata         /* Source start address in Flash */
    movs r3, #0
    b copy_data_loop_check

copy_data_loop:
    ldr r4, [r2, r3]         /* Load word from Flash */
    str r4, [r0, r3]         /* Store word to SRAM */
    adds r3, r3, #4          /* Increment offset */

copy_data_loop_check:
    adds r4, r0, r3          /* Calculate current dest address */
    cmp r4, r1               /* Compare with end address */
    bcc copy_data_loop       /* Continue if not done */

    /* Zero .bss section */
    ldr r0, =_sbss           /* Start of BSS */
    ldr r1, =_ebss           /* End of BSS */
    movs r2, #0
    b zero_bss_loop_check

zero_bss_loop:
    str r2, [r0]             /* Store zero */
    adds r0, r0, #4          /* Next word */

zero_bss_loop_check:
    cmp r0, r1               /* Check if done */
    bcc zero_bss_loop        /* Continue if not done */

    /* Call C++ constructors (if any) */
    /* bl __libc_init_array */  /* Uncomment if using C++ */

    /* Call main function */
    bl main

    /* Infinite loop if main returns */
hang:
    b hang

.size Reset_Handler, .-Reset_Handler

/* End of startup code */
