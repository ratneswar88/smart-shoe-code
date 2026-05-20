# Smart Belt Hardware Design Guide
## Posture Monitoring + Waist Circumference Tracking

---

## Table of Contents
1. [System Architecture](#system-architecture)
2. [Component Selection](#component-selection)
3. [Circuit Schematics](#circuit-schematics)
4. [PCB Layout Guidelines](#pcb-layout-guidelines)
5. [Mechanical Integration](#mechanical-integration)
6. [Power Budget Analysis](#power-budget-analysis)
7. [Assembly Instructions](#assembly-instructions)

---

## 1. System Architecture

### Block Diagram
```
┌─────────────────────────────────────────────────────┐
│                   ESP32-S3-WROOM-1                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │   Dual Core │  │  BLE 5.0    │  │  WiFi       │ │
│  │   240MHz    │  │  Radio      │  │  (Optional) │ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                       │
│  GPIO/I2C/ADC/PWM Interfaces                         │
└───┬─────────┬─────────┬─────────┬─────────┬─────────┘
    │         │         │         │         │
    │         │         │         │         │
┌───▼───┐ ┌──▼───┐ ┌───▼────┐ ┌──▼────┐ ┌──▼────┐
│ IMU   │ │Strain│ │ Haptic │ │ LED   │ │ USB-C │
│ Sensor│ │Gauge │ │ Motor  │ │       │ │Charging│
│MPU9250│ │+ Amp │ │        │ │       │ │       │
└───────┘ └──────┘ └────────┘ └───────┘ └───────┘
```

### Two Module Design Approach

**Module 1: Posture Monitor**
- ESP32-S3 (primary)
- MPU9250 IMU
- Haptic feedback motor
- 500mAh LiPo battery
- Location: Back of belt (lumbar region)

**Module 2: Waist Sensor**
- Strain gauge array
- INA128 instrumentation amplifier
- NTC thermistor (temperature compensation)
- Connected to Module 1 via flex cable
- Location: Front/side of belt (away from buckle)

---

## 2. Component Selection

### Core Components

#### ESP32-S3-WROOM-1
- **Supplier**: Espressif / Mouser / DigiKey
- **Part Number**: ESP32-S3-WROOM-1-N8R2
- **Specs**:
  - Dual-core Xtensa LX7 @ 240MHz
  - 8MB Flash, 2MB PSRAM
  - BLE 5.0, WiFi 802.11b/g/n
  - 45 GPIO pins
  - 12-bit ADC, I2C, SPI, UART
- **Price**: ~$3-5 USD

#### IMU: MPU9250 (or ICM-20948)
- **Supplier**: InvenSense / TDK
- **Part Number**: MPU-9250 or ICM-20948
- **Specs**:
  - 9-DOF: 3-axis accel + gyro + mag
  - 16-bit ADC
  - I2C/SPI interface
  - Programmable interrupt
  - ±2/±4/±8/±16g accel range
  - ±250/±500/±1000/±2000 dps gyro range
- **Price**: $8-15 USD
- **Alternative**: BMI270 + BMM150 (cheaper, ~$5)

#### Strain Gauge
- **Supplier**: Omega Engineering / Vishay
- **Recommended**: BF350-3AA
- **Specs**:
  - Resistance: 350Ω
  - Gauge Factor: 2.1 ± 1%
  - Size: 3mm x 5mm (flexible)
  - Material: Constantan foil
  - Temperature range: -20°C to +80°C
- **Price**: $10-20 USD
- **Quantity**: 2 gauges (for full bridge, optional)

**Alternative Option**: FlexiForce A201 Force Sensor
- Easier to integrate
- Lower precision but adequate
- ~$15 USD

#### Instrumentation Amplifier: INA128
- **Supplier**: Texas Instruments
- **Part Number**: INA128PA (DIP) or INA128UA (SOIC)
- **Specs**:
  - Gain: 1-10,000 (programmable via resistor)
  - Input offset: 50μV max
  - CMRR: 120dB
  - Low noise: 9nV/√Hz
  - Supply: ±2.25V to ±18V (use +5V)
- **Price**: $5-8 USD
- **Gain Setting**: Rg = 50.5kΩ / (Gain - 1)
  - For Gain = 500: Rg = 101Ω

### Power System

#### Battery: 500mAh LiPo
- **Supplier**: Adafruit / SparkFun / Aliexpress
- **Specs**:
  - Capacity: 500mAh
  - Voltage: 3.7V nominal (4.2V max, 3.0V min)
  - Size: ~30mm x 20mm x 5mm
  - Protection circuit: Built-in (essential!)
- **Price**: $6-10 USD
- **Expected Life**: 2-4 weeks with power optimization

#### Charging IC: TP4056
- **Supplier**: Generic / Aliexpress / Amazon
- **Part Number**: TP4056 module
- **Features**:
  - USB-C input
  - 1A charge current (programmable)
  - Charge/discharge protection
  - LED indicators
- **Price**: $1-3 USD (complete module)

#### Voltage Regulator: AP2112K-3.3
- **Supplier**: Diodes Inc / LCSC
- **Part Number**: AP2112K-3.3TRG1
- **Specs**:
  - Output: 3.3V
  - Max current: 600mA
  - Low dropout: 250mV @ 600mA
  - Quiescent current: 55μA
  - SOT-23-5 package
- **Price**: $0.30-0.50 USD

### Sensors & Peripherals

#### Thermistor: NTC 10kΩ
- **Part Number**: NTCLE100E3103JB0
- **Specs**: 10kΩ @ 25°C, β=3950K
- **Price**: $0.20-0.50 USD

#### Haptic Motor: Vibration Motor
- **Supplier**: Adafruit / Pololu
- **Part Number**: Vibrating Mini Motor Disc
- **Specs**:
  - Voltage: 3V nominal
  - Current: 40-60mA
  - Size: 10mm diameter x 3mm
- **Price**: $2-4 USD

#### MOSFET for Motor Control
- **Part Number**: 2N7002 (N-channel)
- **Specs**: 60V, 300mA, SOT-23
- **Price**: $0.10-0.20 USD

### Passive Components

#### Resistors (0805 SMD)
- **Bridge resistors**: 350Ω, 1% tolerance (x3)
- **Gain resistor**: 100Ω, 0.1% tolerance
- **Pull-ups**: 4.7kΩ (x2 for I2C)
- **Thermistor divider**: 10kΩ
- **LED current limiting**: 1kΩ
- **Total**: ~$2-3 USD for kit

#### Capacitors (0805 SMD)
- **Power decoupling**: 0.1μF, 10μF, 100μF
- **Analog filtering**: 1nF, 10nF
- **Total**: ~$2-3 USD for kit

### Connectors & Mechanical

#### Flex Cable Connector
- **Supplier**: Molex / JST / Aliexpress
- **Part Number**: FFC/FPC connector 0.5mm pitch, 12-pin
- **Price**: $0.50-1.00 USD

#### USB-C Connector
- **Part**: USB-C 2.0 receptacle
- **Price**: $0.50-1.00 USD

---

## 3. Circuit Schematics

### 3.1 Main Power Supply

```
USB-C (VBUS 5V)
     │
     ├──────┬─────► TP4056 Module
     │      │         │
     │      │    VBAT│      LiPo Battery
     │      └─────────┤─────(+)─── 500mAh 3.7V
     │                └─────(-)─── GND
     │
     │       Battery Output (3.7-4.2V)
     ├──────────┬──────────────────────────┐
     │          │                          │
     │       10μF│                          │
     │          ┴                          │
     │         GND                AP2112K-3.3
     │                           VIN │ VOUT
     │                           ────┤
     │                           EN  │  3.3V Rail
     │                           ────┤  └────┬─────► ESP32-S3
     │                           GND │       │        IMU
     │                            ┴          │        Peripherals
     │                           GND      100μF
     │                                       ┴
     │                                      GND
     └────────────────────────────────────────────► Battery Voltage Monitor
                                                     (ADC pin for level)
```

### 3.2 IMU Interface (I2C)

```
ESP32-S3                                    MPU9250
                                          ┌──────────┐
GPIO21 (SDA) ──┬─── 4.7kΩ ─── 3.3V      │   VDD    │──── 3.3V
               │                          │          │
               └──────────────────────────┤   SDA    │
                                          │          │
GPIO22 (SCL) ──┬─── 4.7kΩ ─── 3.3V      │   SCL    │
               │                          │          │
               └──────────────────────────┤   INT    │──┐
                                          │          │  │
GPIO4 (INT)  ──────────────────────────────────────────┘
                                          │   GND    │
                                          └──────────┘
                                               ┴
                                              GND

Decoupling: 0.1μF + 10μF caps on VDD pin close to IC
```

### 3.3 Strain Gauge Wheatstone Bridge + Amplifier

```
Bridge Supply: 5V (from battery through boost converter or USB)

Wheatstone Bridge (Quarter-Bridge Configuration):
                        
        5V ──┬─── R1 (350Ω) ───┬─── GND
             │                  │
             │                  │
            SG (350Ω)          R2 (350Ω)
          (Strain Gauge)        │
             │                  │
             └──── V+ ──────────┴──── V-
                    │              │
                    │              │
                  (Differential output to amplifier)

INA128 Instrumentation Amplifier:
                                          ┌─────────────┐
     V+ (from bridge) ────────────────────┤ IN+      OUT├───┬──► ADC (ESP32 GPIO34)
                                          │             │   │
     V- (from bridge) ────────────────────┤ IN-         │   │
                                          │             │  10kΩ
                                          │    Rg       │   │
                        100Ω (0.1%)       │             │   ┴
                    ┌───────Ω──────┐     │  (Gain Set) │  GND
                    │               │     │             │
                    │    Pin 1      │     │    Pin 8    │
                    └───────────────┘     │             │
                                          │   V+  = 5V  │──── 5V
                                          │   V-  = GND │──── GND
                                          │   Ref = GND │──── GND
                                          └─────────────┘

Filtering: 1nF cap between OUT and GND for noise reduction

Gain Calculation:
    Gain = 1 + (50.5kΩ / Rg)
    For Rg = 100Ω: Gain ≈ 506
```

**Important Notes:**
- Use matched resistors (1% tolerance) for R1, R2
- Keep traces short and symmetric
- Add guard traces around analog signals
- Use ground plane under INA128
- Optional: Use full-bridge (4 gauges) for better sensitivity

### 3.4 Temperature Sensor (Thermistor)

```
3.3V ──┬─── 10kΩ ───┬─── ADC (ESP32 GPIO35)
       │            │
       │         NTC 10kΩ
       │         (@25°C)
       │            │
       └────────────┴─── GND

Capacitor: 10nF parallel to thermistor for filtering
```

### 3.5 Haptic Motor Driver

```
ESP32-S3 GPIO5 ────┬────── 1kΩ ────► Gate (2N7002 MOSFET)
                   │
                   │                   ┌─── Drain ─── Haptic Motor (+)
                 10kΩ                  │
                   │                2N7002
                   │                   │
                  GND                  └─── Source ─── GND

Motor (+) ────────────────────────────┴─── 3.3V (battery direct)

Flyback Diode: 1N4148 across motor (cathode to 3.3V, anode to MOSFET drain)
```

### 3.6 Status LED

```
ESP32-S3 GPIO2 ────── 1kΩ ────┬────► Anode (LED)
                               │
                            LED (Red)
                               │
                          ────▼────
                               │
                              GND
```

### 3.7 Flex Cable Connection (Module 1 to Module 2)

```
Module 1 (Main)                        Module 2 (Waist Sensor)
ESP32-S3                               Strain Gauge + Amplifier
                                       
Pin 1:  5V ────────────────────────────► Bridge Supply
Pin 2:  GND ───────────────────────────► Ground
Pin 3:  GPIO34 (ADC) ◄─────────────────── INA128 Output
Pin 4:  GPIO35 (ADC) ◄─────────────────── Thermistor Output
Pin 5:  3.3V ──────────────────────────► Op-amp Supply
Pin 6-12: Reserved for expansion

Use shielded flex cable if length > 10cm
```

---

## 4. PCB Layout Guidelines

### Module 1: Main Controller (Posture Monitor)

**Board Dimensions**: 35mm x 25mm x 1.6mm (2-layer PCB)

**Component Placement**:
```
┌─────────────────────────────────────┐
│  [USB-C]         [TP4056 Module]    │
│                                      │
│         [ESP32-S3-WROOM-1]          │
│              (Center)                │
│                                      │
│  [MPU9250]              [AP2112K]   │
│   (I2C)                              │
│                         [Battery    │
│  [LED]  [Haptic]         Connector] │
│                                      │
│         [Flex Connector]             │
└─────────────────────────────────────┘
```

**Layer Stack**:
- Top: Components + signal routing
- Bottom: Ground plane (flood fill) + power traces

**Critical Traces**:
- I2C: Keep < 10cm, 0.3mm width, no vias
- ADC: Guard with GND traces, keep away from digital
- Power: 0.5-1.0mm width for 3.3V/5V rails

### Module 2: Waist Sensor

**Board Dimensions**: 25mm x 15mm x 0.8mm (flex PCB or rigid-flex)

**Component Placement**:
```
┌─────────────────────────┐
│   [Flex Connector]      │
│                         │
│   [INA128]  [Thermistor]│
│                         │
│   [Strain Gauge Pads]   │
│        (4 pads)         │
└─────────────────────────┘
```

**Strain Gauge Mounting**:
- Use 4-pad pattern for gauge soldering
- Pads: 2mm x 1mm with 3mm spacing
- Solder mask relief for flexibility
- Consider polyimide flex PCB for durability

---

## 5. Mechanical Integration

### Belt-Mounted Enclosure Design

**Module 1 Enclosure** (3D printed or injection molded):
```
Dimensions: 40mm x 30mm x 15mm

Material Options:
- TPU 95A (flexible, comfortable)
- PETG (rigid, durable)
- Silicone overmolding (premium)

Features:
- Snap-fit battery compartment
- USB-C port cutout
- Strain relief for flex cable
- Ventilation slots (optional)
- Belt attachment: slide-in clips or velcro backing
```

**Module 2 Enclosure**:
```
Dimensions: 30mm x 20mm x 8mm

Material: Flexible TPU (must bend with belt)

Features:
- Fully encapsulated strain gauge
- Waterproof to IP54
- Adhesive backing for belt attachment
- Strain isolation mounting
```

### Belt Integration Methods

#### Option A: Embedded in Belt Material
- Cut slot in belt fabric
- Insert flex PCB with strain gauge
- Overmold with silicone for waterproofing
- Most seamless but requires custom belt

#### Option B: External Clip-On Module
- Attach enclosure to inside of belt with clips
- Adjustable position for different body types
- Removable for washing
- Easier to prototype

#### Option C: Velcro-Attached Sensor Pad
- Thin sensor module (< 5mm)
- Velcro backing on belt
- User can reposition
- Best for testing

---

## 6. Power Budget Analysis

### Current Consumption

| Component | Active Mode | Idle Mode | Sleep Mode |
|-----------|-------------|-----------|------------|
| ESP32-S3 BLE | 45mA | 15mA | 10μA |
| MPU9250 @ 50Hz | 3.7mA | 0.45mA | 8μA |
| INA128 + Bridge | 2.0mA | 2.0mA | 2.0mA |
| Haptic Motor | 60mA (pulse) | 0mA | 0mA |
| LED | 10mA (on) | 0mA | 0mA |
| Total (typical) | **60mA** | **17.5mA** | **2.0mA** |

### Battery Life Calculation

**Scenario 1**: Active monitoring (BLE connected, continuous IMU)
- Current: 60mA average
- Battery: 500mAh
- Life: 500mAh / 60mA = **8.3 hours**

**Scenario 2**: Normal use (mostly idle, periodic BLE updates)
- Active 10%, Idle 90%
- Average: (60mA × 0.1) + (17.5mA × 0.9) = 21.75mA
- Life: 500mAh / 21.75mA = **23 hours**

**Scenario 3**: Power optimized (motion interrupts, aggressive sleep)
- Active 2%, Idle 8%, Sleep 90%
- Average: (60 × 0.02) + (17.5 × 0.08) + (2 × 0.9) = 4.4mA
- Life: 500mAh / 4.4mA = **114 hours = 4.7 days**

**Target**: With proper power management, achieve **2-4 weeks** battery life
- Requires deep sleep between movements
- Wake on motion interrupt
- Aggressive BLE connection interval tuning

### Power Optimization Strategies

1. **Motion Detection**: Use MPU9250 interrupt to wake ESP32
2. **BLE Optimization**:
   - Connection interval: 100-200ms (not 7.5ms)
   - Slave latency: 4-10 (skip unnecessary events)
   - Reduce notification rate when idle
3. **Adaptive Sampling**: 10Hz idle, 50Hz active
4. **Strain Gauge Duty Cycle**: Power down bridge when not measuring
5. **Watchdog Timer**: Auto-sleep after 5 min inactivity

---

## 7. Assembly Instructions

### Step 1: SMD Component Soldering

**Order of Assembly**:
1. ESP32-S3 module (hot air or reflow oven)
2. AP2112K regulator
3. Resistors and capacitors (0805 size)
4. INA128 (SOIC-8)
5. Connectors (USB-C, flex cable, battery)

**Tools Required**:
- Soldering iron (fine tip, temp-controlled)
- Hot air station (for ESP32 module)
- Solder paste (for reflow)
- Flux pen
- Tweezers
- Magnification (microscope or loupe)

### Step 2: Through-Hole Components

1. Haptic motor (solder wires, then heat-shrink)
2. LED (note polarity!)
3. Battery connector (JST-PH 2-pin)

### Step 3: Strain Gauge Bonding

**Critical Process**:
1. Clean PCB pads with isopropyl alcohol
2. Apply thin layer of cyanoacrylate (CA) adhesive
3. Position strain gauge with tweezer (alignment is critical!)
4. Hold for 30 seconds, cure for 24 hours
5. Solder gauge leads with minimal heat (< 2 seconds per pad)
6. Apply thin coat of silicone conformal coating for protection

**Alternative**: Use conductive epoxy (easier but lower performance)

### Step 4: Programming & Testing

1. Connect USB-C cable
2. Install ESP32 Arduino core
3. Upload firmware via Arduino IDE / PlatformIO
4. Test each subsystem:
   - Power supply voltages (3.3V, 5V)
   - IMU I2C communication
   - Strain gauge ADC readings
   - BLE advertising
   - Haptic motor

### Step 5: Calibration Procedure

**IMU Calibration**:
1. Place belt on flat, level surface
2. Run gyro bias calibration (built-in MPU9250 function)
3. Store calibration to flash

**Strain Gauge Calibration**:
1. Measure waist with tape measure (accurate to 1mm)
2. Wear belt at normal tightness
3. Send calibration command with measured value
4. System calculates strain-to-circumference mapping
5. Validate with multiple measurements

### Step 6: Enclosure Assembly

1. Insert PCB into enclosure base
2. Connect battery (polarity check!)
3. Route flex cable through strain relief
4. Snap or screw on cover
5. Attach to belt using chosen mounting method
6. Seal USB port with rubber plug (if waterproofing needed)

---

## Bill of Materials (BOM)

### Complete Cost Breakdown

| Component | Qty | Unit Price | Total |
|-----------|-----|------------|-------|
| ESP32-S3-WROOM-1 | 1 | $4.00 | $4.00 |
| MPU9250 | 1 | $12.00 | $12.00 |
| INA128 | 1 | $6.00 | $6.00 |
| Strain Gauge (BF350) | 2 | $15.00 | $30.00 |
| TP4056 Module | 1 | $2.00 | $2.00 |
| LiPo Battery 500mAh | 1 | $8.00 | $8.00 |
| AP2112K Regulator | 1 | $0.40 | $0.40 |
| Haptic Motor | 1 | $3.00 | $3.00 |
| Thermistor NTC | 1 | $0.30 | $0.30 |
| MOSFETs, Resistors, Caps | | | $5.00 |
| Connectors (USB-C, JST) | | | $3.00 |
| PCB (2-layer, 35x25mm) | 1 | $2.00 | $2.00 |
| Flex Cable + Connector | 1 | $2.00 | $2.00 |
| Enclosure (3D printed TPU) | 1 | $5.00 | $5.00 |
| **TOTAL** | | | **$82.70** |

*Prices are approximate and based on single-unit purchases. Bulk discounts available.*

---

## Recommended Development Kit

For prototyping, consider using development boards:

1. **ESP32-S3 DevKit** ($8-12)
2. **MPU9250 Breakout Board** ($10)
3. **INA128 Breakout / Wheatstone Bridge Module** ($15)
4. **Breadboard prototyping** before PCB

**Total Dev Kit**: ~$40-50 (vs $83 for custom PCB)

---

## Next Steps

1. **Phase 1**: Breadboard prototype with dev boards
2. **Phase 2**: Design PCB in KiCad / Eagle
3. **Phase 3**: Order PCB from JLCPCB / PCBWay ($5 for 5 boards)
4. **Phase 4**: Assembly and testing
5. **Phase 5**: 3D print enclosures (iterate design)
6. **Phase 6**: Belt integration and field testing

**Timeline**: 4-6 weeks for complete working prototype

---

## Troubleshooting Guide

### Common Issues

**IMU Not Detected**:
- Check I2C pull-ups (4.7kΩ)
- Verify 3.3V supply to IMU
- Scan I2C bus: `i2cdetect` command
- Try lower I2C clock speed (100kHz)

**Strain Gauge Noisy Readings**:
- Verify bridge balance (measure bridge output at rest)
- Check INA128 gain resistor value
- Add LC filter on power supply
- Use shielded cable for strain gauge leads
- Ensure proper grounding (star ground topology)

**Short Battery Life**:
- Verify ESP32 enters deep sleep (measure current)
- Check for floating GPIO pins (add pull-downs)
- Disable unused peripherals (WiFi, Bluetooth when not needed)
- Monitor battery voltage (low voltage = high current draw)

**BLE Connection Issues**:
- Reduce advertising interval for faster connection
- Check RF shielding (keep antenna area clear)
- Update BLE stack firmware
- Verify MTU size and connection parameters

---

## Safety Considerations

1. **Battery Safety**:
   - Always use protected LiPo cells
   - Include overcurrent protection
   - Never charge above 4.2V
   - Temperature monitoring during charging

2. **Skin Contact**:
   - Use biocompatible materials for enclosure
   - Avoid sharp edges
   - Ensure no exposed metal contacts

3. **Electrical Safety**:
   - Isolate USB ground from battery ground (if possible)
   - Use proper ESD protection on all external connectors
   - Fuse on battery line (500mA PTC resettable fuse)

4. **Testing**:
   - Never wear device during initial power-on testing
   - Monitor temperature during extended use
   - Test all failure modes (short circuit, reverse polarity, etc.)

---

## Regulatory Notes

If commercializing, consider:

- **FCC Certification** (USA): Required for BLE devices
- **CE Marking** (EU): EMC and safety compliance
- **Medical Device Classification**: May require FDA review if making health claims
- **IP Rating**: Determine water/dust resistance level needed

---

End of Hardware Design Guide
