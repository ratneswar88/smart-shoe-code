/**
 * FreeRTOS Practical Interview Examples
 * ======================================
 * 
 * Complete, working code examples for common FreeRTOS patterns.
 * Ready to compile and demonstrate in interviews.
 */

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "timers.h"

// ============================================================================
// EXAMPLE 1: Producer-Consumer Pattern with Queue
// ============================================================================

/**
 * SCENARIO: Sensor task reads data, processing task handles it
 * DEMONSTRATES: Queue usage, task communication, blocking
 */

QueueHandle_t xSensorQueue;

void vSensorTask(void *pvParameters) {
    uint32_t sensorValue;
    TickType_t xLastWakeTime = xTaskGetTickCount();
    
    while(1) {
        // Read sensor (simulated)
        sensorValue = read_sensor();
        
        // Send to queue (block up to 10ms if full)
        if (xQueueSend(xSensorQueue, &sensorValue, pdMS_TO_TICKS(10)) != pdPASS) {
            // Queue full - data lost!
            error_count++;
        }
        
        // Sample every 100ms precisely
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(100));
    }
}

void vProcessingTask(void *pvParameters) {
    uint32_t receivedValue;
    
    while(1) {
        // Wait forever for data
        if (xQueueReceive(xSensorQueue, &receivedValue, portMAX_DELAY) == pdPASS) {
            // Process data
            process_data(receivedValue);
            
            // If over threshold, trigger action
            if (receivedValue > THRESHOLD) {
                xTaskNotifyGive(xAlarmTaskHandle);
            }
        }
    }
}

void example1_create(void) {
    // Create queue: 10 items of uint32_t
    xSensorQueue = xQueueCreate(10, sizeof(uint32_t));
    configASSERT(xSensorQueue != NULL);
    
    // Create tasks
    xTaskCreate(vSensorTask, "Sensor", 256, NULL, 2, NULL);
    xTaskCreate(vProcessingTask, "Process", 512, NULL, 2, NULL);
}

// ============================================================================
// EXAMPLE 2: Binary Semaphore for ISR Synchronization
// ============================================================================

/**
 * SCENARIO: UART interrupt signals task to process data
 * DEMONSTRATES: ISR-safe operations, semaphore signaling
 */

SemaphoreHandle_t xUartSemaphore;
volatile uint8_t uartRxBuffer[256];
volatile uint16_t uartRxHead = 0;

// UART interrupt handler
void UART_IRQHandler(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    
    if (UART->SR & UART_SR_RXNE) {
        // Read data
        uint8_t data = UART->DR;
        uartRxBuffer[uartRxHead++] = data;
        
        // Signal processing task
        xSemaphoreGiveFromISR(xUartSemaphore, &xHigherPriorityTaskWoken);
        
        // Yield if higher priority task woken
        portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
    }
}

void vUartProcessTask(void *pvParameters) {
    while(1) {
        // Wait for semaphore (block indefinitely)
        if (xSemaphoreTake(xUartSemaphore, portMAX_DELAY) == pdTRUE) {
            // Data available - process it
            taskENTER_CRITICAL();
            uint8_t data = uartRxBuffer[--uartRxHead];
            taskEXIT_CRITICAL();
            
            // Process received data
            handle_uart_data(data);
        }
    }
}

void example2_create(void) {
    // Create binary semaphore (initially empty)
    xUartSemaphore = xSemaphoreCreateBinary();
    configASSERT(xUartSemaphore != NULL);
    
    xTaskCreate(vUartProcessTask, "UART", 256, NULL, 3, NULL);
    
    // Enable UART interrupt
    NVIC_EnableIRQ(UART_IRQn);
}

// ============================================================================
// EXAMPLE 3: Mutex for Shared Resource Protection
// ============================================================================

/**
 * SCENARIO: Multiple tasks share I2C bus
 * DEMONSTRATES: Mutex usage, critical resource protection
 */

SemaphoreHandle_t xI2cMutex;

bool I2C_Write(uint8_t addr, uint8_t *data, uint16_t len) {
    bool success = false;
    
    // Acquire mutex (wait up to 100ms)
    if (xSemaphoreTake(xI2cMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        // Critical section - exclusive I2C access
        success = i2c_write_blocking(addr, data, len);
        
        // Release mutex
        xSemaphoreGive(xI2cMutex);
    }
    
    return success;
}

void vSensor1Task(void *pvParameters) {
    uint8_t data[2];
    
    while(1) {
        // Read sensor at address 0x48
        if (I2C_Write(0x48, data, 2)) {
            process_sensor1(data);
        }
        
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void vSensor2Task(void *pvParameters) {
    uint8_t data[2];
    
    while(1) {
        // Read different sensor at 0x68
        if (I2C_Write(0x68, data, 2)) {
            process_sensor2(data);
        }
        
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

void example3_create(void) {
    // Create mutex
    xI2cMutex = xSemaphoreCreateMutex();
    configASSERT(xI2cMutex != NULL);
    
    xTaskCreate(vSensor1Task, "Sensor1", 256, NULL, 2, NULL);
    xTaskCreate(vSensor2Task, "Sensor2", 256, NULL, 2, NULL);
}

// ============================================================================
// EXAMPLE 4: Counting Semaphore for Resource Pool
// ============================================================================

/**
 * SCENARIO: Limited number of DMA channels available
 * DEMONSTRATES: Counting semaphore, resource management
 */

#define MAX_DMA_CHANNELS 4
SemaphoreHandle_t xDmaSemaphore;

bool DMA_Acquire(void) {
    // Try to acquire DMA channel (wait up to 50ms)
    if (xSemaphoreTake(xDmaSemaphore, pdMS_TO_TICKS(50)) == pdTRUE) {
        return true;  // Channel acquired
    }
    return false;  // All channels busy
}

void DMA_Release(void) {
    xSemaphoreGive(xDmaSemaphore);
}

void vDmaUserTask(void *pvParameters) {
    while(1) {
        if (DMA_Acquire()) {
            // Use DMA channel
            perform_dma_transfer();
            
            // Release when done
            DMA_Release();
        } else {
            // No channels available, wait and retry
            vTaskDelay(pdMS_TO_TICKS(10));
        }
        
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void example4_create(void) {
    // Create counting semaphore: 4 available resources
    xDmaSemaphore = xSemaphoreCreateCounting(MAX_DMA_CHANNELS, MAX_DMA_CHANNELS);
    configASSERT(xDmaSemaphore != NULL);
    
    // Create multiple tasks competing for DMA
    for (int i = 0; i < 6; i++) {
        xTaskCreate(vDmaUserTask, "DMA", 256, NULL, 2, NULL);
    }
}

// ============================================================================
// EXAMPLE 5: Software Timer for Periodic Events
// ============================================================================

/**
 * SCENARIO: LED blinks, watchdog feeding, periodic logging
 * DEMONSTRATES: Software timers, callback functions
 */

TimerHandle_t xLedTimer, xWatchdogTimer;

void vLedTimerCallback(TimerHandle_t xTimer) {
    // Toggle LED every 500ms
    LED_Toggle();
}

void vWatchdogTimerCallback(TimerHandle_t xTimer) {
    // Feed watchdog every 100ms
    IWDG_Reload();
}

void example5_create(void) {
    // Create auto-reload timer for LED (500ms period)
    xLedTimer = xTimerCreate("LED",
                             pdMS_TO_TICKS(500),
                             pdTRUE,  // Auto-reload
                             NULL,
                             vLedTimerCallback);
    configASSERT(xLedTimer != NULL);
    
    // Create auto-reload timer for watchdog (100ms period)
    xWatchdogTimer = xTimerCreate("Watchdog",
                                  pdMS_TO_TICKS(100),
                                  pdTRUE,
                                  NULL,
                                  vWatchdogTimerCallback);
    configASSERT(xWatchdogTimer != NULL);
    
    // Start both timers
    xTimerStart(xLedTimer, 0);
    xTimerStart(xWatchdogTimer, 0);
}

// ============================================================================
// EXAMPLE 6: Task Notification for Lightweight Signaling
// ============================================================================

/**
 * SCENARIO: Button ISR signals task to handle press
 * DEMONSTRATES: Task notifications (faster than semaphore)
 */

TaskHandle_t xButtonTaskHandle = NULL;

void BUTTON_IRQHandler(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    
    // Clear interrupt flag
    EXTI->PR = EXTI_PR_PR0;
    
    // Notify task (increment notification value)
    vTaskNotifyGiveFromISR(xButtonTaskHandle, &xHigherPriorityTaskWoken);
    
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

void vButtonTask(void *pvParameters) {
    uint32_t pressCount = 0;
    
    while(1) {
        // Wait for notification (blocks indefinitely)
        pressCount += ulTaskNotifyTake(pdTRUE,  // Clear on exit
                                       portMAX_DELAY);
        
        // Handle button press
        handle_button_press();
        
        // Debounce delay
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

void example6_create(void) {
    xTaskCreate(vButtonTask, "Button", 256, NULL, 3, &xButtonTaskHandle);
    
    // Enable button interrupt
    NVIC_EnableIRQ(EXTI0_IRQn);
}

// ============================================================================
// EXAMPLE 7: Multi-Task Communication Pattern
// ============================================================================

/**
 * SCENARIO: Sensor → Filter → Logger → Display pipeline
 * DEMONSTRATES: Multiple queues, task chain
 */

QueueHandle_t xRawDataQueue, xFilteredQueue, xLogQueue;

void vSensorTaskPipeline(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    
    while(1) {
        uint16_t rawData = ADC_Read();
        xQueueSend(xRawDataQueue, &rawData, 0);
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(10));
    }
}

void vFilterTask(void *pvParameters) {
    uint16_t rawData, filtered;
    
    while(1) {
        if (xQueueReceive(xRawDataQueue, &rawData, portMAX_DELAY) == pdPASS) {
            filtered = moving_average_filter(rawData);
            xQueueSend(xFilteredQueue, &filtered, 0);
        }
    }
}

void vLoggerTask(void *pvParameters) {
    uint16_t data;
    
    while(1) {
        if (xQueueReceive(xFilteredQueue, &data, portMAX_DELAY) == pdPASS) {
            log_to_sd_card(data);
            xQueueSend(xLogQueue, &data, 0);
        }
    }
}

void vDisplayTask(void *pvParameters) {
    uint16_t data;
    
    while(1) {
        if (xQueueReceive(xLogQueue, &data, portMAX_DELAY) == pdPASS) {
            update_display(data);
        }
    }
}

void example7_create(void) {
    xRawDataQueue = xQueueCreate(10, sizeof(uint16_t));
    xFilteredQueue = xQueueCreate(10, sizeof(uint16_t));
    xLogQueue = xQueueCreate(5, sizeof(uint16_t));
    
    xTaskCreate(vSensorTaskPipeline, "Sensor", 256, NULL, 4, NULL);
    xTaskCreate(vFilterTask, "Filter", 256, NULL, 3, NULL);
    xTaskCreate(vLoggerTask, "Logger", 512, NULL, 2, NULL);
    xTaskCreate(vDisplayTask, "Display", 256, NULL, 1, NULL);
}

// ============================================================================
// EXAMPLE 8: Stack Monitoring and Error Handling
// ============================================================================

/**
 * SCENARIO: Monitor system health
 * DEMONSTRATES: Stack checking, error hooks
 */

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    // Stack overflow detected!
    // Log error
    error_log("Stack overflow in task: %s", pcTaskName);
    
    // In production: Reset or enter safe mode
    NVIC_SystemReset();
    
    // In debug: Infinite loop for debugging
    while(1) {
        LED_Red_Toggle();
        for(volatile int i = 0; i < 1000000; i++);
    }
}

void vApplicationMallocFailedHook(void) {
    // Heap exhausted!
    error_log("Heap allocation failed!");
    NVIC_SystemReset();
}

void vMonitorTask(void *pvParameters) {
    while(1) {
        // Check free heap
        size_t freeHeap = xPortGetFreeHeapSize();
        if (freeHeap < 1024) {
            warning_log("Low heap: %d bytes", freeHeap);
        }
        
        // Check stack high water marks
        UBaseType_t stackRemaining = uxTaskGetStackHighWaterMark(NULL);
        if (stackRemaining < 64) {
            warning_log("Low stack: %d words", stackRemaining);
        }
        
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

// ============================================================================
// EXAMPLE 9: Deferred Interrupt Processing
// ============================================================================

/**
 * SCENARIO: Complex processing triggered by interrupt
 * DEMONSTRATES: Keep ISR short, defer work to task
 */

TaskHandle_t xProcessingTaskHandle;
volatile uint32_t adcData[100];
volatile bool dataReady = false;

void ADC_DMA_IRQHandler(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    
    // DMA transfer complete
    if (DMA->LISR & DMA_LISR_TCIF0) {
        DMA->LIFCR = DMA_LIFCR_CTCIF0;  // Clear flag
        
        dataReady = true;
        
        // Signal task to process
        vTaskNotifyGiveFromISR(xProcessingTaskHandle, &xHigherPriorityTaskWoken);
        portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
    }
}

void vDeferredProcessingTask(void *pvParameters) {
    uint32_t localData[100];
    
    while(1) {
        // Wait for notification from ISR
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        
        if (dataReady) {
            // Copy data safely
            taskENTER_CRITICAL();
            memcpy(localData, (void*)adcData, sizeof(adcData));
            dataReady = false;
            taskEXIT_CRITICAL();
            
            // Process data (can take long time)
            complex_fft_analysis(localData, 100);
        }
    }
}

void example9_create(void) {
    xTaskCreate(vDeferredProcessingTask, "Process", 1024, NULL, 3, 
                &xProcessingTaskHandle);
}

// ============================================================================
// EXAMPLE 10: Priority Inversion Demonstration
// ============================================================================

/**
 * SCENARIO: Show priority inversion and solution
 * DEMONSTRATES: Why mutexes are better than semaphores
 */

// PROBLEM: Using semaphore (no priority inheritance)
SemaphoreHandle_t xResourceSemaphore;

void vLowPriorityTask(void *pvParameters) {
    while(1) {
        xSemaphoreTake(xResourceSemaphore, portMAX_DELAY);
        
        // Simulate long work (1 second)
        vTaskDelay(pdMS_TO_TICKS(1000));
        
        xSemaphoreGive(xResourceSemaphore);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void vMediumPriorityTask(void *pvParameters) {
    while(1) {
        // Busy work - blocks high priority task!
        busy_work();
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void vHighPriorityTask(void *pvParameters) {
    while(1) {
        // High priority task starves waiting for low priority!
        xSemaphoreTake(xResourceSemaphore, portMAX_DELAY);
        critical_work();
        xSemaphoreGive(xResourceSemaphore);
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

// SOLUTION: Use mutex (has priority inheritance)
SemaphoreHandle_t xResourceMutex;

void vLowPriorityTaskFixed(void *pvParameters) {
    while(1) {
        xSemaphoreTake(xResourceMutex, portMAX_DELAY);
        // When high priority task waits, this task inherits its priority!
        // Now it can preempt medium priority task
        vTaskDelay(pdMS_TO_TICKS(1000));
        xSemaphoreGive(xResourceMutex);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void example10_create(void) {
    // Problem version
    xResourceSemaphore = xSemaphoreCreateBinary();
    xSemaphoreGive(xResourceSemaphore);
    
    // Solution version
    xResourceMutex = xSemaphoreCreateMutex();
    
    // Create tasks with different priorities
    xTaskCreate(vLowPriorityTaskFixed, "Low", 256, NULL, 1, NULL);
    xTaskCreate(vMediumPriorityTask, "Med", 256, NULL, 2, NULL);
    xTaskCreate(vHighPriorityTask, "High", 256, NULL, 3, NULL);
}

// ============================================================================
// MAIN APPLICATION
// ============================================================================

int main(void) {
    // Initialize hardware
    HAL_Init();
    SystemClock_Config();
    
    // Create one or more examples
    example1_create();  // Producer-consumer
    example2_create();  // ISR synchronization
    example3_create();  // Shared resource
    // ... etc
    
    // Start scheduler
    vTaskStartScheduler();
    
    // Should never reach here
    while(1);
}

/**
 * INTERVIEW TIPS:
 * ===============
 * 
 * 1. Always check return values (pdPASS/pdFAIL)
 * 2. Use vTaskDelayUntil for precise timing
 * 3. Keep ISRs short - defer to tasks
 * 4. Use mutexes (not semaphores) for shared resources
 * 5. Enable stack overflow detection
 * 6. Monitor heap usage
 * 7. Use task notifications when possible (faster)
 * 8. Understand priority inversion
 * 9. Know your tick rate and timing resolution
 * 10. Use FreeRTOS-aware debugger
 */
