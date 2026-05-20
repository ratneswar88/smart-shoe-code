/**
 * ============================================================================
 * FINITE STATE MACHINES (FSM) - COMPLETE TUTORIAL WITH THEORY
 * ============================================================================
 * 
 * This tutorial covers:
 * PART 1: Theoretical Foundations & Mathematical Models
 * PART 2: FSM Design Methodology
 * PART 3: Implementation Patterns (4 methods)
 * PART 4: Practical Examples (Button Debouncing, Communication Protocol)
 * PART 5: Advanced Topics & Best Practices
 */

#include <cstdint>
#include <cstdio>

// ============================================================================
// PART 1: THEORETICAL FOUNDATIONS
// ============================================================================

/**
 * WHAT IS A FINITE STATE MACHINE? (FORMAL DEFINITION)
 * ====================================================
 * 
 * MATHEMATICAL MODEL:
 * ------------------
 * A Finite State Machine (FSM) is a 5-tuple (Q, Σ, δ, q₀, F) where:
 * 
 * Q  = Finite set of STATES
 * Σ  = Finite set of INPUT symbols (EVENTS)
 * δ  = TRANSITION function: δ: Q × Σ → Q
 * q₀ = INITIAL state (q₀ ∈ Q)
 * F  = Set of FINAL/ACCEPTING states (F ⊆ Q)
 * 
 * In plain English:
 * - System can only be in ONE state at a time
 * - Events cause transitions between states
 * - Transition function defines what happens next
 * - System starts in initial state
 * - May have final/accepting states (not always used)
 * 
 * 
 * INTUITIVE UNDERSTANDING:
 * ------------------------
 * Think of FSM as a machine with a finite number of "modes" or "conditions."
 * At any moment, it's in exactly ONE mode. When something happens (an event),
 * it may switch to another mode following predefined rules.
 * 
 * 
 * REAL-WORLD EXAMPLES:
 * --------------------
 * 
 * Example 1: Traffic Light
 * Q  = {RED, YELLOW, GREEN}                    (3 states)
 * Σ  = {Timer_Expired}                         (1 event)
 * q₀ = RED                                     (initial state)
 * δ: RED + Timer_Expired → GREEN
 *    GREEN + Timer_Expired → YELLOW
 *    YELLOW + Timer_Expired → RED
 * 
 * Example 2: Door Lock
 * Q  = {LOCKED, UNLOCKED}
 * Σ  = {Correct_Code, Wrong_Code, Timeout}
 * q₀ = LOCKED
 * δ: LOCKED + Correct_Code → UNLOCKED / Open_Lock()
 *    LOCKED + Wrong_Code → LOCKED / Beep_Error()
 *    UNLOCKED + Timeout → LOCKED / Close_Lock()
 * 
 * Example 3: Phone Call
 * Q  = {IDLE, RINGING, CONNECTED, BUSY}
 * Σ  = {Incoming_Call, Answer, Hangup, Busy_Signal}
 * q₀ = IDLE
 * 
 * 
 * WHY FSM THEORY MATTERS FOR EMBEDDED ENGINEERS:
 * ===============================================
 * 
 * 1. PREDICTABILITY
 *    - Every possible system state is defined
 *    - Behavior is deterministic (no surprises)
 *    - Critical for safety systems (medical, automotive, aerospace)
 *    - Can predict system response to any input sequence
 * 
 * 2. VERIFIABILITY
 *    - Can mathematically prove correctness
 *    - Can verify all states are reachable
 *    - Can detect deadlocks (unreachable exit)
 *    - Can find unreachable states (dead code)
 *    - Model checking tools can verify properties
 * 
 * 3. DOCUMENTATION
 *    - State diagram = visual specification
 *    - Clear communication with non-programmers
 *    - Easy code reviews
 *    - Maintainable over years
 * 
 * 4. TESTABILITY
 *    - Each state testable independently
 *    - Each transition testable
 *    - Test coverage measurable
 *    - Easy to find edge cases
 * 
 * 5. COMPLEXITY MANAGEMENT
 *    - Breaks complex behavior into simple pieces
 *    - Each state handles one condition
 *    - Reduces cognitive load
 *    - Scales better than nested if-else
 * 
 * 
 * TYPES OF FINITE STATE MACHINES:
 * ================================
 * 
 * 1. MEALY MACHINE
 *    - Output depends on: CURRENT STATE + INPUT
 *    - Actions occur on TRANSITIONS
 *    - More common in embedded systems
 *    - Example:
 *        State: IDLE
 *        Event: Button_Press
 *        Transition: IDLE → ACTIVE
 *        Action during transition: Turn_On_LED()
 * 
 * 2. MOORE MACHINE
 *    - Output depends on: CURRENT STATE only
 *    - Actions occur WITHIN STATES
 *    - May require more states than Mealy
 *    - Example:
 *        State: LED_ON_STATE
 *        Output: LED is on (continuous while in state)
 * 
 * 3. DETERMINISTIC FSM (DFA)
 *    - For each (state, input) pair: exactly ONE next state
 *    - Most embedded systems use DFA
 *    - Predictable, testable, reliable
 * 
 * 4. NON-DETERMINISTIC FSM (NFA)
 *    - Multiple possible next states for same input
 *    - Useful in theoretical computer science
 *    - Can be converted to DFA
 *    - Rarely used in embedded systems
 * 
 * 
 * FSM vs OTHER CONTROL STRUCTURES:
 * =================================
 * 
 * WHEN TO USE FSM:
 * ----------------
 * ✓ System has multiple operating modes
 * ✓ Event-driven behavior
 * ✓ Complex timing sequences
 * ✓ Protocol implementation
 * ✓ User interface logic
 * ✓ Safety-critical state management
 * ✓ Anything with "modes," "phases," or "stages"
 * 
 * WHEN NOT TO USE FSM:
 * --------------------
 * ✗ Simple sequential code (1-2 states)
 * ✗ Pure mathematical calculations
 * ✗ One-time initialization sequences
 * ✗ Simple if-else logic
 * 
 * 
 * COMPARISON: SPAGHETTI CODE vs FSM
 * ==================================
 * 
 * APPROACH 1: Multiple flags (BAD)
 * ---------------------------------
 */

bool buttonPressed = false;
bool longPressHandled = false;
bool ledIsOn = false;
uint32_t pressTime = 0;

void approach1_spaghetti() {
    // Read button
    if (readButton() && !buttonPressed) {
        buttonPressed = true;
        pressTime = millis();
        longPressHandled = false;
    }
    
    if (!readButton() && buttonPressed) {
        buttonPressed = false;
        if (!longPressHandled) {
            // Short press - toggle LED
            ledIsOn = !ledIsOn;
            setLED(ledIsOn);
        }
    }
    
    if (buttonPressed && (millis() - pressTime > 1000) && !longPressHandled) {
        // Long press
        longPressHandled = true;
        // Do something different
        blinkLED();
    }
}

/**
 * Problems with flag-based approach:
 * - Hard to see overall behavior
 * - Multiple variables track "state"
 * - Easy to introduce bugs (forgot to reset flag?)
 * - Difficult to add features
 * - Not clear what "state" system is in
 * - Race conditions possible
 * 
 * 
 * APPROACH 2: FSM (GOOD)
 * -----------------------
 */

enum class ButtonState {
    IDLE,
    PRESSED,
    LONG_PRESS
};

ButtonState buttonState = ButtonState::IDLE;
uint32_t pressStartTime = 0;

void approach2_fsm() {
    switch (buttonState) {
        case ButtonState::IDLE:
            if (readButton()) {
                buttonState = ButtonState::PRESSED;
                pressStartTime = millis();
            }
            break;
            
        case ButtonState::PRESSED:
            if (!readButton()) {
                // Released - short press
                toggleLED();
                buttonState = ButtonState::IDLE;
            } else if (millis() - pressStartTime > 1000) {
                // Held for 1 second - long press
                buttonState = ButtonState::LONG_PRESS;
                blinkLED();
            }
            break;
            
        case ButtonState::LONG_PRESS:
            if (!readButton()) {
                buttonState = ButtonState::IDLE;
            }
            break;
    }
}

/**
 * Benefits of FSM approach:
 * + Clear states (IDLE, PRESSED, LONG_PRESS)
 * + One variable tracks everything
 * + Easy to understand at a glance
 * + Easy to extend (add DOUBLE_CLICK state)
 * + Matches state diagram exactly
 * + Self-documenting
 * 
 * 
 * FSM COMPONENTS (DETAILED):
 * ===========================
 * 
 * 1. STATES
 *    Definition: Distinct conditions/configurations of the system
 *    Characteristics:
 *    - System is in exactly ONE state at any time
 *    - States should be mutually exclusive
 *    - States should be meaningful and distinct
 *    
 *    Examples:
 *    - Motor: STOPPED, STARTING, RUNNING, STOPPING
 *    - Connection: DISCONNECTED, CONNECTING, CONNECTED, ERROR
 *    - Battery: CHARGING, FULL, DISCHARGING, LOW, CRITICAL
 * 
 * 2. EVENTS (Inputs)
 *    Definition: Triggers that cause state changes
 *    Types:
 *    - External events: Button press, sensor trigger, message received
 *    - Internal events: Timer expiry, counter threshold
 *    - Conditional events: Temperature > 80°C
 *    
 *    Properties:
 *    - Events are instantaneous
 *    - Events may carry data (button_press with button_id)
 *    - Events may be queued or immediate
 * 
 * 3. TRANSITIONS
 *    Definition: Rules for changing from one state to another
 *    Format: [Current State] + [Event] [Condition] → [Next State]
 *    
 *    Example: IDLE + button_press [if armed] → ACTIVE
 *    
 *    Properties:
 *    - Can have guard conditions
 *    - Should be deterministic
 *    - Can be self-transitions (stay in same state)
 * 
 * 4. ACTIONS
 *    Definition: Things that happen during transitions or in states
 *    
 *    Types:
 *    a) Entry Actions: Execute when entering a state
 *       Example: Enter RUNNING → start_motor()
 *    
 *    b) Exit Actions: Execute when leaving a state
 *       Example: Exit RUNNING → stop_motor()
 *    
 *    c) Transition Actions: Execute during state change
 *       Example: IDLE → ACTIVE: turn_on_led()
 *    
 *    d) State Actions: Execute while in a state
 *       Example: While in RUNNING: monitor_temperature()
 * 
 * 
 * STATE DIAGRAM NOTATION:
 * =======================
 * 
 * Standard UML notation:
 * 
 *     ╔═══════════╗                 ┌───────────┐
 *     ║  Initial  ║  event/action   │   State   │
 *  ●──║   State   ║────────────────>│           │
 *     ╚═══════════╝                 └───────────┘
 *          │                              │
 *          │ event[condition]/action      │
 *          └──────────────────────────────┘
 * 
 * Elements:
 * ● = Initial state marker
 * ╔═══╗ = Initial state (or use ●)
 * ┌───┐ = Normal state
 * ──>  = Transition arrow
 * event/action = Transition label
 * [condition] = Guard condition
 * ◉ = Final/accepting state (double circle)
 * 
 * 
 * Example: Complete Button FSM Diagram
 * 
 *         ┌──────────────┐
 *         │              │
 *         ↓              │ button_released
 *     ╔════════╗         │
 *  ●─>║  IDLE  ║         │
 *     ╚════════╝         │
 *         │              │
 *         │ button_pressed
 *         │ /start_timer()
 *         ↓              │
 *     ┌────────────┐     │
 *     │  PRESSED   │     │
 *     └────────────┘     │
 *         │              │
 *         │ timer>1000ms │
 *         │ /long_press_action()
 *         ↓              │
 *     ┌────────────┐     │
 *     │ LONG_PRESS │     │
 *     └────────────┘     │
 *         │              │
 *         │ button_released
 *         └──────────────┘
 */

// Placeholder functions
bool readButton() { return false; }
void setLED(bool on) { }
void toggleLED() { }
void blinkLED() { }
uint32_t millis() { return 0; }

// ============================================================================
// PART 2: FSM IMPLEMENTATION PATTERNS
// ============================================================================

// ----------------------------------------------------------------------------
// PATTERN 1: SWITCH-CASE FSM (Most Common in Embedded)
// ----------------------------------------------------------------------------

/**
 * ADVANTAGES:
 * + Simple to understand
 * + Fast execution
 * + Easy to debug
 * + Small code size
 * 
 * DISADVANTAGES:
 * - Can become messy with many states
 * - Need to manually track state
 * 
 * BEST FOR: Small to medium FSMs (3-10 states)
 */

// Example: Simple LED Blinker FSM
enum class LedState {
    OFF,
    ON
};

class LedBlinkerFsm {
public:
    LedBlinkerFsm() : currentState_(LedState::OFF) {}
    
    // Call this periodically (e.g., every 1ms)
    void update() {
        switch (currentState_) {
            case LedState::OFF:
                // Entry action (do once when entering state)
                if (stateChanged_) {
                    turnLedOff();
                    startTimer(500);  // 500ms timeout
                    stateChanged_ = false;
                }
                
                // Check for transition
                if (timerExpired()) {
                    transitionTo(LedState::ON);
                }
                break;
                
            case LedState::ON:
                if (stateChanged_) {
                    turnLedOn();
                    startTimer(500);
                    stateChanged_ = false;
                }
                
                if (timerExpired()) {
                    transitionTo(LedState::OFF);
                }
                break;
        }
    }
    
private:
    LedState currentState_;
    bool stateChanged_ = true;
    uint32_t timerStart_ = 0;
    uint32_t timerDuration_ = 0;
    
    void transitionTo(LedState newState) {
        currentState_ = newState;
        stateChanged_ = true;
    }
    
    void startTimer(uint32_t ms) {
        timerStart_ = millis();
        timerDuration_ = ms;
    }
    
    bool timerExpired() {
        return (millis() - timerStart_) >= timerDuration_;
    }
    
    void turnLedOn() { /* Hardware code */ }
    void turnLedOff() { /* Hardware code */ }
    uint32_t millis() { return 0; }  // Placeholder
};

// ----------------------------------------------------------------------------
// PATTERN 2: STATE TABLE FSM (Data-Driven)
// ----------------------------------------------------------------------------

/**
 * ADVANTAGES:
 * + Very clear structure
 * + Easy to see all transitions
 * + Easy to modify behavior
 * + Table can be stored in ROM
 * 
 * DISADVANTAGES:
 * - Uses more memory (table storage)
 * - Slower than switch-case (table lookup)
 * 
 * BEST FOR: Complex FSMs that need to be configurable
 */

// Example: Door Control FSM

enum class DoorState {
    CLOSED,
    OPENING,
    OPEN,
    CLOSING
};

enum class DoorEvent {
    OPEN_BUTTON,
    CLOSE_BUTTON,
    FULLY_OPEN,
    FULLY_CLOSED,
    OBSTACLE
};

struct StateTableEntry {
    DoorState currentState;
    DoorEvent event;
    DoorState nextState;
    void (*action)();  // Function to call on transition
};

// Action functions
void startOpeningMotor() { printf("Motor: Opening\n"); }
void startClosingMotor() { printf("Motor: Closing\n"); }
void stopMotor() { printf("Motor: Stop\n"); }
void reverseMotor() { printf("Motor: Reverse\n"); }

// State transition table
const StateTableEntry stateTable[] = {
    // Current State    Event              Next State         Action
    {DoorState::CLOSED, DoorEvent::OPEN_BUTTON,   DoorState::OPENING, startOpeningMotor},
    {DoorState::OPENING,DoorEvent::FULLY_OPEN,    DoorState::OPEN,    stopMotor},
    {DoorState::OPENING,DoorEvent::OBSTACLE,      DoorState::CLOSING, reverseMotor},
    {DoorState::OPEN,   DoorEvent::CLOSE_BUTTON,  DoorState::CLOSING, startClosingMotor},
    {DoorState::CLOSING,DoorEvent::FULLY_CLOSED,  DoorState::CLOSED,  stopMotor},
    {DoorState::CLOSING,DoorEvent::OBSTACLE,      DoorState::OPENING, reverseMotor},
};

class DoorFsm {
public:
    DoorFsm() : currentState_(DoorState::CLOSED) {}
    
    void handleEvent(DoorEvent event) {
        // Search table for matching transition
        for (const auto& entry : stateTable) {
            if (entry.currentState == currentState_ && 
                entry.event == event) {
                // Found matching transition
                
                // Execute action
                if (entry.action) {
                    entry.action();
                }
                
                // Change state
                currentState_ = entry.nextState;
                break;
            }
        }
    }
    
    DoorState getState() const { return currentState_; }
    
private:
    DoorState currentState_;
};

// Usage example
void example_door_fsm() {
    DoorFsm door;
    
    printf("Initial state: CLOSED\n");
    
    door.handleEvent(DoorEvent::OPEN_BUTTON);  // CLOSED → OPENING
    door.handleEvent(DoorEvent::FULLY_OPEN);   // OPENING → OPEN
    door.handleEvent(DoorEvent::CLOSE_BUTTON); // OPEN → CLOSING
    door.handleEvent(DoorEvent::OBSTACLE);     // CLOSING → OPENING (safety!)
    door.handleEvent(DoorEvent::FULLY_OPEN);   // OPENING → OPEN
}

// ----------------------------------------------------------------------------
// PATTERN 3: FUNCTION POINTER FSM (Object-Oriented)
// ----------------------------------------------------------------------------

/**
 * ADVANTAGES:
 * + Very clean code
 * + Easy to add new states
 * + Each state is isolated
 * + Easy to unit test
 * 
 * DISADVANTAGES:
 * - Uses more RAM (function pointers)
 * - Slightly more complex
 * 
 * BEST FOR: Complex FSMs with many states and actions
 */

class ButtonFsm {
public:
    // State handler function type
    typedef void (ButtonFsm::*StateHandler)();
    
    ButtonFsm() : currentHandler_(&ButtonFsm::stateReleased) {}
    
    // Call this regularly
    void update() {
        // Execute current state handler
        (this->*currentHandler_)();
    }
    
    // Events
    void onButtonDown() { buttonPressed_ = true; }
    void onButtonUp() { buttonPressed_ = false; }
    
private:
    StateHandler currentHandler_;
    bool buttonPressed_ = false;
    uint32_t pressTime_ = 0;
    
    // State: RELEASED
    void stateReleased() {
        if (buttonPressed_) {
            pressTime_ = millis();
            currentHandler_ = &ButtonFsm::statePressed;
            printf("State: PRESSED\n");
        }
    }
    
    // State: PRESSED
    void statePressed() {
        if (!buttonPressed_) {
            uint32_t duration = millis() - pressTime_;
            
            if (duration < 1000) {
                printf("Short press detected\n");
            }
            
            currentHandler_ = &ButtonFsm::stateReleased;
            printf("State: RELEASED\n");
        }
        else if (millis() - pressTime_ >= 1000) {
            currentHandler_ = &ButtonFsm::stateLongPress;
            printf("State: LONG_PRESS\n");
        }
    }
    
    // State: LONG_PRESS
    void stateLongPress() {
        if (!buttonPressed_) {
            printf("Long press detected\n");
            currentHandler_ = &ButtonFsm::stateReleased;
            printf("State: RELEASED\n");
        }
    }
    
    uint32_t millis() { return 0; }  // Placeholder
};

// ----------------------------------------------------------------------------
// PATTERN 4: STATE PATTERN (Full OOP with C++)
// ----------------------------------------------------------------------------

/**
 * ADVANTAGES:
 * + Most flexible
 * + Best for very complex FSMs
 * + Each state is a separate class
 * + Easy to extend with polymorphism
 * 
 * DISADVANTAGES:
 * - Uses most memory (vtable, objects)
 * - More complex to set up
 * - Slower (virtual function calls)
 * 
 * BEST FOR: Very complex FSMs, or when you need inheritance
 * NOT RECOMMENDED for simple embedded systems (too much overhead)
 */

// Forward declaration
class TrafficLightContext;

// Base State class
class TrafficLightState {
public:
    virtual ~TrafficLightState() = default;
    virtual void enter() = 0;
    virtual void update(TrafficLightContext& context) = 0;
    virtual const char* getName() = 0;
};

// Context (the FSM itself)
class TrafficLightContext {
public:
    void setState(TrafficLightState* newState) {
        currentState_ = newState;
        currentState_->enter();
    }
    
    void update() {
        if (currentState_) {
            currentState_->update(*this);
        }
    }
    
    void setTimer(uint32_t ms) {
        timerStart_ = millis();
        timerDuration_ = ms;
    }
    
    bool timerExpired() {
        return (millis() - timerStart_) >= timerDuration_;
    }
    
private:
    TrafficLightState* currentState_ = nullptr;
    uint32_t timerStart_ = 0;
    uint32_t timerDuration_ = 0;
    
    uint32_t millis() { return 0; }  // Placeholder
};

// Concrete states
class RedState : public TrafficLightState {
public:
    void enter() override {
        printf("RED light ON\n");
    }
    
    void update(TrafficLightContext& context) override {
        if (context.timerExpired()) {
            context.setState(&greenState_);
        }
    }
    
    const char* getName() override { return "RED"; }
    
private:
    static class GreenState greenState_;
};

class GreenState : public TrafficLightState {
public:
    void enter() override {
        printf("GREEN light ON\n");
    }
    
    void update(TrafficLightContext& context) override {
        if (context.timerExpired()) {
            context.setState(&yellowState_);
        }
    }
    
    const char* getName() override { return "GREEN"; }
    
private:
    static class YellowState yellowState_;
};

class YellowState : public TrafficLightState {
public:
    void enter() override {
        printf("YELLOW light ON\n");
    }
    
    void update(TrafficLightContext& context) override {
        if (context.timerExpired()) {
            context.setState(&redState_);
        }
    }
    
    const char* getName() override { return "YELLOW"; }
    
private:
    static RedState redState_;
};

// ============================================================================
// PART 3: PRACTICAL EMBEDDED FSM EXAMPLES
// ============================================================================

// ----------------------------------------------------------------------------
// EXAMPLE 1: Button Debouncing FSM (ESSENTIAL for embedded!)
// ----------------------------------------------------------------------------

/**
 * PROBLEM: Mechanical buttons "bounce" - they don't transition cleanly
 * 
 * Without debouncing:
 *   Button signal: ___/‾\/\/‾‾‾‾\___
 *   MCU reads:     ___/‾‾‾\‾\_/‾‾\___  (multiple presses!)
 * 
 * With debouncing FSM:
 *   MCU reads:     ___/‾‾‾‾‾‾‾‾‾\___  (one clean press)
 * 
 * FSM STATES:
 *   IDLE → DEBOUNCE_PRESS → PRESSED → DEBOUNCE_RELEASE → IDLE
 */

enum class ButtonDebounceState {
    IDLE,
    DEBOUNCE_PRESS,
    PRESSED,
    DEBOUNCE_RELEASE
};

class ButtonDebouncer {
public:
    ButtonDebouncer() 
        : state_(ButtonDebounceState::IDLE)
        , debounceTime_(20)  // 20ms debounce time
    {}
    
    // Call this regularly (e.g., every 1ms from timer ISR)
    void update(bool rawButtonState) {
        switch (state_) {
            case ButtonDebounceState::IDLE:
                if (rawButtonState) {  // Button pressed
                    debounceTimer_ = millis();
                    state_ = ButtonDebounceState::DEBOUNCE_PRESS;
                }
                break;
                
            case ButtonDebounceState::DEBOUNCE_PRESS:
                if (!rawButtonState) {
                    // Button released during debounce - ignore
                    state_ = ButtonDebounceState::IDLE;
                }
                else if (millis() - debounceTimer_ >= debounceTime_) {
                    // Debounce time passed, button is stable
                    state_ = ButtonDebounceState::PRESSED;
                    onButtonPressed();  // Trigger event!
                }
                break;
                
            case ButtonDebounceState::PRESSED:
                if (!rawButtonState) {  // Button released
                    debounceTimer_ = millis();
                    state_ = ButtonDebounceState::DEBOUNCE_RELEASE;
                }
                break;
                
            case ButtonDebounceState::DEBOUNCE_RELEASE:
                if (rawButtonState) {
                    // Button pressed again during debounce
                    state_ = ButtonDebounceState::PRESSED;
                }
                else if (millis() - debounceTimer_ >= debounceTime_) {
                    state_ = ButtonDebounceState::IDLE;
                    onButtonReleased();  // Trigger event!
                }
                break;
        }
    }
    
    bool isPressed() const {
        return state_ == ButtonDebounceState::PRESSED;
    }
    
private:
    ButtonDebounceState state_;
    uint32_t debounceTimer_;
    uint32_t debounceTime_;
    
    void onButtonPressed() {
        printf("Button PRESSED (debounced)\n");
    }
    
    void onButtonReleased() {
        printf("Button RELEASED (debounced)\n");
    }
    
    uint32_t millis() { return 0; }  // Placeholder
};

// ----------------------------------------------------------------------------
// EXAMPLE 2: UART Protocol FSM
// ----------------------------------------------------------------------------

/**
 * PROBLEM: Receiving data over UART with specific protocol
 * 
 * PROTOCOL: <START_BYTE><LENGTH><DATA...><CHECKSUM>
 * Example:  0xAA 0x04 0x12 0x34 0x56 0x78 0xB4
 * 
 * FSM ensures we parse data correctly and handle errors
 */

enum class UartRxState {
    WAIT_START,
    READ_LENGTH,
    READ_DATA,
    READ_CHECKSUM
};

class UartProtocolFsm {
public:
    UartProtocolFsm() : state_(UartRxState::WAIT_START) {}
    
    // Call this when byte received (from UART ISR or main loop)
    void receiveByte(uint8_t byte) {
        switch (state_) {
            case UartRxState::WAIT_START:
                if (byte == 0xAA) {  // Start byte
                    checksum_ = 0;
                    state_ = UartRxState::READ_LENGTH;
                }
                break;
                
            case UartRxState::READ_LENGTH:
                if (byte > 0 && byte <= 32) {  // Valid length
                    length_ = byte;
                    dataIndex_ = 0;
                    checksum_ += byte;
                    state_ = UartRxState::READ_DATA;
                } else {
                    // Invalid length, reset
                    state_ = UartRxState::WAIT_START;
                }
                break;
                
            case UartRxState::READ_DATA:
                dataBuffer_[dataIndex_++] = byte;
                checksum_ += byte;
                
                if (dataIndex_ >= length_) {
                    state_ = UartRxState::READ_CHECKSUM;
                }
                break;
                
            case UartRxState::READ_CHECKSUM:
                if (byte == checksum_) {
                    // Valid packet received!
                    processPacket(dataBuffer_, length_);
                } else {
                    printf("Checksum error!\n");
                }
                state_ = UartRxState::WAIT_START;
                break;
        }
    }
    
private:
    UartRxState state_;
    uint8_t dataBuffer_[32];
    uint8_t length_;
    uint8_t dataIndex_;
    uint8_t checksum_;
    
    void processPacket(uint8_t* data, uint8_t len) {
        printf("Valid packet received: %d bytes\n", len);
    }
};

// ----------------------------------------------------------------------------
// EXAMPLE 3: Motor Control FSM
// ----------------------------------------------------------------------------

/**
 * STATES: STOPPED → ACCELERATING → RUNNING → DECELERATING → STOPPED
 */

enum class MotorState {
    STOPPED,
    ACCELERATING,
    RUNNING,
    DECELERATING
};

class MotorControlFsm {
public:
    MotorControlFsm() 
        : state_(MotorState::STOPPED)
        , speed_(0)
        , targetSpeed_(0)
    {}
    
    // Commands
    void start(uint16_t targetSpeed) {
        if (state_ == MotorState::STOPPED) {
            targetSpeed_ = targetSpeed;
            state_ = MotorState::ACCELERATING;
        }
    }
    
    void stop() {
        targetSpeed_ = 0;
        if (state_ != MotorState::STOPPED) {
            state_ = MotorState::DECELERATING;
        }
    }
    
    // Call this periodically (e.g., every 10ms)
    void update() {
        switch (state_) {
            case MotorState::STOPPED:
                speed_ = 0;
                setMotorPwm(0);
                break;
                
            case MotorState::ACCELERATING:
                speed_ += 10;  // Acceleration rate
                
                if (speed_ >= targetSpeed_) {
                    speed_ = targetSpeed_;
                    state_ = MotorState::RUNNING;
                }
                
                setMotorPwm(speed_);
                break;
                
            case MotorState::RUNNING:
                if (speed_ != targetSpeed_) {
                    // Target changed
                    if (targetSpeed_ < speed_) {
                        state_ = MotorState::DECELERATING;
                    } else {
                        state_ = MotorState::ACCELERATING;
                    }
                }
                setMotorPwm(speed_);
                break;
                
            case MotorState::DECELERATING:
                if (speed_ > 10) {
                    speed_ -= 10;  // Deceleration rate
                } else {
                    speed_ = 0;
                    state_ = MotorState::STOPPED;
                }
                setMotorPwm(speed_);
                break;
        }
    }
    
    MotorState getState() const { return state_; }
    uint16_t getSpeed() const { return speed_; }
    
private:
    MotorState state_;
    uint16_t speed_;
    uint16_t targetSpeed_;
    
    void setMotorPwm(uint16_t speed) {
        // Set PWM duty cycle based on speed
        printf("Motor PWM: %d\n", speed);
    }
};

// ============================================================================
// BEST PRACTICES FOR FSM IN EMBEDDED SYSTEMS
// ============================================================================

/**
 * 1. KEEP STATES SIMPLE
 *    - Each state should do ONE thing
 *    - Easy to understand at a glance
 * 
 * 2. USE ENTRY/EXIT ACTIONS
 *    - Setup when entering state
 *    - Cleanup when leaving state
 * 
 * 3. AVOID INFINITE LOOPS IN STATES
 *    - FSM should be called periodically
 *    - Don't block in state handlers
 * 
 * 4. HANDLE ALL EVENTS IN ALL STATES
 *    - Even if action is "ignore"
 *    - Prevents undefined behavior
 * 
 * 5. USE TIMEOUTS
 *    - Prevent getting stuck in states
 *    - Handle communication timeouts
 * 
 * 6. DRAW THE STATE DIAGRAM FIRST
 *    - Makes implementation much easier
 *    - Documents the design
 * 
 * 7. CHOOSE RIGHT PATTERN FOR COMPLEXITY
 *    - Simple FSM (< 5 states): Switch-case
 *    - Medium FSM (5-15 states): Function pointers or State table
 *    - Complex FSM (> 15 states): Consider hierarchical FSM
 * 
 * 8. TEST EACH STATE AND TRANSITION
 *    - Unit test individual states
 *    - Integration test state sequences
 * 
 * 9. LOG STATE CHANGES (IN DEBUG)
 *    - Makes debugging much easier
 *    - Can be disabled in production
 * 
 * 10. USE ENUM CLASS (C++)
 *     - Prevents type confusion
 *     - Compiler catches errors
 */

/**
 * SUMMARY:
 * ========
 * 
 * FSM is one of the most useful patterns in embedded programming.
 * 
 * Use FSM when you have:
 * - Multiple modes of operation
 * - Event-driven behavior
 * - Protocol handling
 * - User interfaces
 * - Safety-critical state management
 * 
 * Choose implementation based on complexity:
 * - Small: Switch-case
 * - Medium: State table or Function pointers
 * - Large: Hierarchical FSM or State pattern
 * 
 * Next: See STM32 ISR tutorial for using FSM with interrupts!
 */
