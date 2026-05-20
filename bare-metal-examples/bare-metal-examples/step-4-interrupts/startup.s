.syntax unified
.cpu cortex-m4
.thumb

/* Vector Table */
.section .vector_table,"a",%progbits
.type vector_table, %object
vector_table:
    .word _estack              /* Initial Stack Pointer */
    .word Reset_Handler        /* Reset Handler */
    .word NMI_Handler          /* NMI Handler */
    .word HardFault_Handler    /* Hard Fault Handler */
    .word MemManage_Handler    /* MPU Fault Handler */
    .word BusFault_Handler     /* Bus Fault Handler */
    .word UsageFault_Handler   /* Usage Fault Handler */
    .word 0                    /* Reserved */
    .word 0                    /* Reserved */
    .word 0                    /* Reserved */
    .word 0                    /* Reserved */
    .word SVC_Handler          /* SVCall Handler */
    .word DebugMon_Handler     /* Debug Monitor Handler */
    .word 0                    /* Reserved */
    .word PendSV_Handler       /* PendSV Handler */
    .word SysTick_Handler      /* SysTick Handler */
.size vector_table, .-vector_table

/* Default handler - weak aliases */
.weak NMI_Handler
.weak HardFault_Handler
.weak MemManage_Handler
.weak BusFault_Handler
.weak UsageFault_Handler
.weak SVC_Handler
.weak DebugMon_Handler
.weak PendSV_Handler
.weak SysTick_Handler

.thumb_func
NMI_Handler:
HardFault_Handler:
MemManage_Handler:
BusFault_Handler:
UsageFault_Handler:
SVC_Handler:
DebugMon_Handler:
PendSV_Handler:
SysTick_Handler:
Default_Handler:
    b Default_Handler

/* Reset Handler */
.section .text.Reset_Handler
.weak Reset_Handler
.type Reset_Handler, %function
Reset_Handler:
    /* Set up stack pointer */
    ldr r0, =_estack
    mov sp, r0
    
    /* Call main function */
    bl main
    
    /* Infinite loop if main returns */
hang:
    b hang
.size Reset_Handler, .-Reset_Handler
