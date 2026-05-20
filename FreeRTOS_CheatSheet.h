/*******************************************************************************
 * FreeRTOS QUICK REFERENCE CHEAT SHEET
 * ============================================================================
 * Essential APIs and concepts for interviews
 ******************************************************************************/

// ============================================================================
// TASK MANAGEMENT
// ============================================================================

// Create task
BaseType_t xTaskCreate(
    TaskFunction_t pvTaskCode,      // void func(void*)
    const char *pcName,              // Name for debug
    uint16_t usStackDepth,           // Stack in words
    void *pvParameters,              // Parameter passed to task
    UBaseType_t uxPriority,          // 0 = lowest
    TaskHandle_t *pxCreatedTask      // Handle (optional)
);

// Delete task
vTaskDelete(TaskHandle_t xTask);    // NULL = self

// Delay
vTaskDelay(TickType_t xTicksToDelay);
vTaskDelayUntil(TickType_t *pxPreviousWakeTime, TickType_t xTimeIncrement);

// Suspend/Resume
vTaskSuspend(TaskHandle_t xTask);
vTaskResume(TaskHandle_t xTask);
vTaskResumeFromISR(TaskHandle_t xTask);

// Priority
vTaskPrioritySet(TaskHandle_t xTask, UBaseType_t uxNewPriority);
UBaseType_t uxTaskPriorityGet(TaskHandle_t xTask);

// Info
UBaseType_t uxTaskGetStackHighWaterMark(TaskHandle_t xTask);  // Min free stack
eTaskState eTaskGetState(TaskHandle_t xTask);

// ============================================================================
// QUEUES
// ============================================================================

// Create
QueueHandle_t xQueueCreate(UBaseType_t uxQueueLength, UBaseType_t uxItemSize);

// Send (from task)
BaseType_t xQueueSend(QueueHandle_t xQueue, const void *pvItemToQueue, TickType_t xTicksToWait);
BaseType_t xQueueSendToBack(QueueHandle_t xQueue, const void *pvItemToQueue, TickType_t xTicksToWait);
BaseType_t xQueueSendToFront(QueueHandle_t xQueue, const void *pvItemToQueue, TickType_t xTicksToWait);

// Send (from ISR)
BaseType_t xQueueSendFromISR(QueueHandle_t xQueue, const void *pvItemToQueue, BaseType_t *pxHigherPriorityTaskWoken);
BaseType_t xQueueSendToBackFromISR(...);
BaseType_t xQueueSendToFrontFromISR(...);

// Receive
BaseType_t xQueueReceive(QueueHandle_t xQueue, void *pvBuffer, TickType_t xTicksToWait);
BaseType_t xQueueReceiveFromISR(QueueHandle_t xQueue, void *pvBuffer, BaseType_t *pxHigherPriorityTaskWoken);

// Peek (read without removing)
BaseType_t xQueuePeek(QueueHandle_t xQueue, void *pvBuffer, TickType_t xTicksToWait);

// Info
UBaseType_t uxQueueMessagesWaiting(QueueHandle_t xQueue);
UBaseType_t uxQueueSpacesAvailable(QueueHandle_t xQueue);

// ============================================================================
// SEMAPHORES
// ============================================================================

// Binary Semaphore (0 or 1)
SemaphoreHandle_t xSemaphoreCreateBinary(void);

// Counting Semaphore (0 to max)
SemaphoreHandle_t xSemaphoreCreateCounting(UBaseType_t uxMaxCount, UBaseType_t uxInitialCount);

// Mutex (with priority inheritance)
SemaphoreHandle_t xSemaphoreCreateMutex(void);
SemaphoreHandle_t xSemaphoreCreateRecursiveMutex(void);

// Take (acquire)
BaseType_t xSemaphoreTake(SemaphoreHandle_t xSemaphore, TickType_t xTicksToWait);
BaseType_t xSemaphoreTakeRecursive(SemaphoreHandle_t xMutex, TickType_t xTicksToWait);

// Give (release)
BaseType_t xSemaphoreGive(SemaphoreHandle_t xSemaphore);
BaseType_t xSemaphoreGiveRecursive(SemaphoreHandle_t xMutex);

// From ISR
BaseType_t xSemaphoreGiveFromISR(SemaphoreHandle_t xSemaphore, BaseType_t *pxHigherPriorityTaskWoken);
BaseType_t xSemaphoreTakeFromISR(SemaphoreHandle_t xSemaphore, BaseType_t *pxHigherPriorityTaskWoken);

// ============================================================================
// TASK NOTIFICATIONS (Lightweight alternative to semaphores)
// ============================================================================

// Give (like semaphore give)
BaseType_t xTaskNotifyGive(TaskHandle_t xTaskToNotify);
void vTaskNotifyGiveFromISR(TaskHandle_t xTaskToNotify, BaseType_t *pxHigherPriorityTaskWoken);

// Take (like semaphore take)
uint32_t ulTaskNotifyTake(BaseType_t xClearCountOnExit, TickType_t xTicksToWait);

// Send value
BaseType_t xTaskNotify(TaskHandle_t xTaskToNotify, uint32_t ulValue, eNotifyAction eAction);
BaseType_t xTaskNotifyFromISR(TaskHandle_t xTaskToNotify, uint32_t ulValue, eNotifyAction eAction, BaseType_t *pxHigherPriorityTaskWoken);

// Wait for value
BaseType_t xTaskNotifyWait(uint32_t ulBitsToClearOnEntry, uint32_t ulBitsToClearOnExit, uint32_t *pulNotificationValue, TickType_t xTicksToWait);

// ============================================================================
// SOFTWARE TIMERS
// ============================================================================

// Create
TimerHandle_t xTimerCreate(
    const char *pcTimerName,
    TickType_t xTimerPeriodInTicks,
    UBaseType_t uxAutoReload,       // pdTRUE = auto-reload
    void *pvTimerID,
    TimerCallbackFunction_t pxCallbackFunction
);

// Control
BaseType_t xTimerStart(TimerHandle_t xTimer, TickType_t xTicksToWait);
BaseType_t xTimerStop(TimerHandle_t xTimer, TickType_t xTicksToWait);
BaseType_t xTimerReset(TimerHandle_t xTimer, TickType_t xTicksToWait);
BaseType_t xTimerChangePeriod(TimerHandle_t xTimer, TickType_t xNewPeriod, TickType_t xTicksToWait);

// From ISR
BaseType_t xTimerStartFromISR(...);
BaseType_t xTimerStopFromISR(...);
BaseType_t xTimerResetFromISR(...);

// ============================================================================
// CRITICAL SECTIONS
// ============================================================================

// Task context
taskENTER_CRITICAL();
taskEXIT_CRITICAL();

// ISR context
UBaseType_t uxSavedInterruptStatus = taskENTER_CRITICAL_FROM_ISR();
taskEXIT_CRITICAL_FROM_ISR(uxSavedInterruptStatus);

// Scheduler suspend (prevents task switching)
vTaskSuspendAll();
xTaskResumeAll();

// ============================================================================
// MEMORY MANAGEMENT
// ============================================================================

void* pvPortMalloc(size_t xWantedSize);
void vPortFree(void *pv);

size_t xPortGetFreeHeapSize(void);
size_t xPortGetMinimumEverFreeHeapSize(void);

// ============================================================================
// COMMON CONSTANTS
// ============================================================================

pdTRUE / pdFALSE                // Boolean values
pdPASS / pdFAIL                 // Return values
portMAX_DELAY                   // Wait forever

pdMS_TO_TICKS(ms)               // Convert milliseconds to ticks
portTICK_PERIOD_MS              // Tick period in ms

// ============================================================================
// TASK STATES
// ============================================================================

eRunning                        // Currently executing
eReady                          // Ready to run
eBlocked                        // Waiting for event
eSuspended                      // Manually suspended
eDeleted                        // Deleted

// ============================================================================
// COMMON PATTERNS
// ============================================================================

// Producer-Consumer
QueueHandle_t xQueue = xQueueCreate(10, sizeof(uint32_t));
xQueueSend(xQueue, &data, portMAX_DELAY);
xQueueReceive(xQueue, &data, portMAX_DELAY);

// ISR Synchronization
SemaphoreHandle_t xSem = xSemaphoreCreateBinary();
// ISR: xSemaphoreGiveFromISR(xSem, &xHigherPriorityTaskWoken);
// Task: xSemaphoreTake(xSem, portMAX_DELAY);

// Shared Resource Protection
SemaphoreHandle_t xMutex = xSemaphoreCreateMutex();
xSemaphoreTake(xMutex, portMAX_DELAY);
// Critical section
xSemaphoreGive(xMutex);

// Periodic Task
TickType_t xLastWakeTime = xTaskGetTickCount();
while(1) {
    // Do work
    vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(100));
}

// Deferred Interrupt Processing
void ISR_Handler(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    vTaskNotifyGiveFromISR(xTaskHandle, &xHigherPriorityTaskWoken);
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

void vTask(void *pvParameters) {
    while(1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        // Process interrupt event
    }
}

// ============================================================================
// CONFIGURATION (FreeRTOSConfig.h)
// ============================================================================

configUSE_PREEMPTION               // 1 = preemptive, 0 = cooperative
configCPU_CLOCK_HZ                 // CPU frequency
configTICK_RATE_HZ                 // Tick frequency (typically 1000)
configMAX_PRIORITIES               // Max priority levels (e.g., 5)
configMINIMAL_STACK_SIZE           // Min stack for idle task
configTOTAL_HEAP_SIZE              // Total heap size
configMAX_TASK_NAME_LEN            // Task name length
configUSE_16_BIT_TICKS             // 0 for 32-bit, 1 for 16-bit
configIDLE_SHOULD_YIELD            // 1 = idle yields to same priority
configUSE_MUTEXES                  // Enable mutexes
configUSE_RECURSIVE_MUTEXES        // Enable recursive mutexes
configUSE_COUNTING_SEMAPHORES      // Enable counting semaphores
configUSE_TIMERS                   // Enable software timers
configTIMER_TASK_PRIORITY          // Timer daemon priority
configTIMER_QUEUE_LENGTH           // Timer command queue length
configTIMER_TASK_STACK_DEPTH       // Timer daemon stack size
configCHECK_FOR_STACK_OVERFLOW     // 0, 1, or 2

// ============================================================================
// HOOKS (Optional callback functions)
// ============================================================================

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName);
void vApplicationMallocFailedHook(void);
void vApplicationIdleHook(void);
void vApplicationTickHook(void);
void vApplicationDaemonTaskStartupHook(void);

// ============================================================================
// DEBUGGING
// ============================================================================

configASSERT(x)                    // Assertion macro
uxTaskGetSystemState()             // Get all task states
vTaskList()                        // Get task list as string
vTaskGetRunTimeStats()             // Get runtime statistics

// ============================================================================
// INTERVIEW QUICK FACTS
// ============================================================================

Q: Tick rate?
A: Typically 1000 Hz (1 ms tick), configured by configTICK_RATE_HZ

Q: Priority range?
A: 0 (lowest) to configMAX_PRIORITIES - 1 (highest)

Q: Task states?
A: Running, Ready, Blocked, Suspended

Q: Difference between semaphore and mutex?
A: Mutex has ownership and priority inheritance, use for shared resources

Q: When to use queue vs semaphore?
A: Queue for data, semaphore for events/synchronization

Q: ISR-safe functions?
A: Only functions ending in "FromISR"

Q: How to avoid priority inversion?
A: Use mutexes (not semaphores) - they have priority inheritance

Q: Context switch time?
A: Typically 50-100 cycles (~1-2 µs on Cortex-M4 at 168 MHz)

Q: Difference between vTaskDelay and vTaskDelayUntil?
A: Delay is relative, DelayUntil is absolute (no drift)

Q: How to check stack usage?
A: uxTaskGetStackHighWaterMark(NULL) returns minimum free stack

/*******************************************************************************
 * END OF CHEAT SHEET
 ******************************************************************************/
