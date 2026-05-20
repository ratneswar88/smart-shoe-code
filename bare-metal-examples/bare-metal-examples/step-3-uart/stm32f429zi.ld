/* STM32F429ZI Linker Script */

/* Memory Layout */
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 2048K
    SRAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 192K
}

/* Stack size - 16KB */
_stack_size = 0x4000;

/* End of RAM - used for initial stack pointer */
_estack = ORIGIN(SRAM) + LENGTH(SRAM);

/* Entry point */
ENTRY(Reset_Handler)

/* Sections */
SECTIONS
{
    /* Vector table must be at the start of flash */
    .vector_table : {
        KEEP(*(.vector_table))
    } > FLASH
    
    /* Program code and constants */
    .text : {
        . = ALIGN(4);
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
        _etext = .;
    } > FLASH
    
    /* Initialized data - copied from flash to SRAM at startup */
    .data : {
        . = ALIGN(4);
        _sdata = .;        /* Start of data in SRAM */
        *(.data*)
        . = ALIGN(4);
        _edata = .;        /* End of data in SRAM */
    } > SRAM AT> FLASH
    
    /* Load address of .data in flash */
    _sidata = LOADADDR(.data);
    
    /* Uninitialized data - zeroed at startup */
    .bss : {
        . = ALIGN(4);
        _sbss = .;         /* Start of BSS */
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;         /* End of BSS */
    } > SRAM
    
    /* Check stack doesn't overflow */
    .stack : {
        . = ALIGN(8);
        _sstack = .;
        . = . + _stack_size;
        . = ALIGN(8);
    } > SRAM
}
