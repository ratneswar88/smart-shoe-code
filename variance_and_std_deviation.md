# Variance and Standard Deviation

## Introduction

While measures of central tendency (mean, median, mode) tell us where data is centered, **variance** and **standard deviation** tell us how spread out or dispersed the data is around that center. These are fundamental measures of variability in statistics.

## Why Variability Matters in Embedded Systems

In sensor-based systems, understanding variability is crucial:

- **Noise characterization**: Quantify sensor noise levels
- **Quality control**: Detect anomalous readings that deviate significantly
- **Power management**: Low-variance data may allow reduced sampling rates
- **Signal processing**: Design appropriate filters based on expected variability
- **Anomaly detection**: Identify unusual patterns that exceed expected variation

---

## Population vs Sample

Before diving into variance, we need to distinguish between:

### Population
- **All possible measurements** from a sensor
- We use **population variance (σ²)** and **population standard deviation (σ)**
- Rare in practice—we usually can't measure infinitely

### Sample
- A **subset of measurements** from the population
- We use **sample variance (s²)** and **sample standard deviation (s)**
- Common in embedded systems—we collect finite data windows

---

## Variance

**Variance** measures the average squared deviation from the mean. It quantifies how far data points spread from the center.

### Population Variance

For a population of N values:

```
σ² = Σ(xᵢ - μ)² / N
```

Where:
- σ² = population variance
- xᵢ = each individual value
- μ = population mean
- N = total number of values

### Sample Variance

For a sample of n values:

```
s² = Σ(xᵢ - x̄)² / (n - 1)
```

Where:
- s² = sample variance
- xᵢ = each sample value
- x̄ = sample mean
- n = sample size
- **(n-1)** = Bessel's correction (provides unbiased estimate)

### Why (n-1) Instead of n?

**Bessel's correction** compensates for the fact that sample variance tends to underestimate population variance. Using (n-1) makes the sample variance an unbiased estimator.

---

## Standard Deviation

**Standard deviation** is simply the square root of variance. It has the same units as the original data, making it more interpretable.

### Population Standard Deviation

```
σ = √(σ²) = √[Σ(xᵢ - μ)² / N]
```

### Sample Standard Deviation

```
s = √(s²) = √[Σ(xᵢ - x̄)² / (n - 1)]
```

---

## Example 1: Temperature Sensor Readings

Consider a temperature sensor taking 8 readings (in °C):

```
Data: [22.1, 22.3, 22.0, 22.4, 22.2, 22.5, 22.1, 22.3]
```

### Step 1: Calculate the Mean

```
x̄ = (22.1 + 22.3 + 22.0 + 22.4 + 22.2 + 22.5 + 22.1 + 22.3) / 8
x̄ = 177.9 / 8 = 22.2375°C
```

### Step 2: Calculate Deviations from Mean

| Reading (xᵢ) | Deviation (xᵢ - x̄) | Squared Deviation (xᵢ - x̄)² |
|--------------|---------------------|------------------------------|
| 22.1 | -0.1375 | 0.0189 |
| 22.3 | 0.0625 | 0.0039 |
| 22.0 | -0.2375 | 0.0564 |
| 22.4 | 0.1625 | 0.0264 |
| 22.2 | -0.0375 | 0.0014 |
| 22.5 | 0.2625 | 0.0689 |
| 22.1 | -0.1375 | 0.0189 |
| 22.3 | 0.0625 | 0.0039 |

### Step 3: Sum of Squared Deviations

```
Σ(xᵢ - x̄)² = 0.0189 + 0.0039 + 0.0564 + 0.0264 + 0.0014 + 0.0689 + 0.0189 + 0.0039
           = 0.1987
```

### Step 4: Calculate Sample Variance

```
s² = Σ(xᵢ - x̄)² / (n - 1)
s² = 0.1987 / 7
s² = 0.0284 °C²
```

### Step 5: Calculate Sample Standard Deviation

```
s = √(s²) = √(0.0284)
s ≈ 0.168°C
```

### Interpretation

The temperature readings have:
- **Mean**: 22.24°C
- **Standard deviation**: 0.168°C

This means most readings fall within ±0.168°C of the mean. The sensor has relatively low noise, which is good for precision applications.

---

## Example 2: Accelerometer Data (X-axis)

An IMU accelerometer records 10 samples while at rest (in g):

```
Data: [0.02, -0.01, 0.03, 0.00, 0.01, -0.02, 0.02, 0.01, -0.01, 0.00]
```

### Step 1: Calculate Mean

```
x̄ = (0.02 - 0.01 + 0.03 + 0.00 + 0.01 - 0.02 + 0.02 + 0.01 - 0.01 + 0.00) / 10
x̄ = 0.05 / 10 = 0.005 g
```

### Step 2: Calculate Deviations

| Reading (xᵢ) | Deviation (xᵢ - x̄) | Squared Deviation |
|--------------|---------------------|-------------------|
| 0.02 | 0.015 | 0.000225 |
| -0.01 | -0.015 | 0.000225 |
| 0.03 | 0.025 | 0.000625 |
| 0.00 | -0.005 | 0.000025 |
| 0.01 | 0.005 | 0.000025 |
| -0.02 | -0.025 | 0.000625 |
| 0.02 | 0.015 | 0.000225 |
| 0.01 | 0.005 | 0.000025 |
| -0.01 | -0.015 | 0.000225 |
| 0.00 | -0.005 | 0.000025 |

### Step 3: Sum of Squared Deviations

```
Σ(xᵢ - x̄)² = 0.002250
```

### Step 4: Sample Variance

```
s² = 0.002250 / 9 = 0.00025 g²
```

### Step 5: Sample Standard Deviation

```
s = √(0.00025) = 0.0158 g
```

### Interpretation

The accelerometer at rest shows:
- **Mean**: 0.005g (small offset/bias)
- **Standard deviation**: 0.0158g (noise level)

This standard deviation represents the sensor's noise floor. Any motion detection algorithm should use a threshold above 2-3 times this value to avoid false triggers.

---

## Python Implementation for Embedded ML

```python
import numpy as np

def calculate_variance_std(data):
    """
    Calculate variance and standard deviation
    
    Parameters:
    data: list or numpy array of sensor readings
    
    Returns:
    dict with mean, variance, and std deviation
    """
    n = len(data)
    
    # Calculate mean
    mean = sum(data) / n
    
    # Calculate squared deviations
    squared_deviations = [(x - mean)**2 for x in data]
    
    # Sample variance (using n-1)
    variance = sum(squared_deviations) / (n - 1)
    
    # Standard deviation
    std_dev = variance ** 0.5
    
    return {
        'mean': mean,
        'variance': variance,
        'std_deviation': std_dev,
        'n': n
    }

# Example: Temperature sensor data
temp_data = [22.1, 22.3, 22.0, 22.4, 22.2, 22.5, 22.1, 22.3]
results = calculate_variance_std(temp_data)

print(f"Mean: {results['mean']:.4f}°C")
print(f"Variance: {results['variance']:.6f}°C²")
print(f"Std Deviation: {results['std_deviation']:.4f}°C")

# Using NumPy (more efficient)
print("\nUsing NumPy:")
print(f"Variance: {np.var(temp_data, ddof=1):.6f}")  # ddof=1 for sample variance
print(f"Std Dev: {np.std(temp_data, ddof=1):.4f}")
```

**Output:**
```
Mean: 22.2375°C
Variance: 0.028393°C²
Std Deviation: 0.1685°C

Using NumPy:
Variance: 0.028393
Std Dev: 0.1685
```

---

## Embedded C Implementation

For resource-constrained microcontrollers:

```c
#include <math.h>
#include <stdint.h>

typedef struct {
    float mean;
    float variance;
    float std_deviation;
} stats_t;

/**
 * Calculate variance and standard deviation
 * 
 * @param data: pointer to data array
 * @param n: number of samples
 * @return: stats structure with results
 */
stats_t calculate_stats(float *data, uint16_t n) {
    stats_t stats;
    float sum = 0.0f;
    float sum_sq_diff = 0.0f;
    
    // Calculate mean
    for (uint16_t i = 0; i < n; i++) {
        sum += data[i];
    }
    stats.mean = sum / n;
    
    // Calculate sum of squared deviations
    for (uint16_t i = 0; i < n; i++) {
        float deviation = data[i] - stats.mean;
        sum_sq_diff += deviation * deviation;
    }
    
    // Sample variance (n-1)
    stats.variance = sum_sq_diff / (n - 1);
    
    // Standard deviation
    stats.std_deviation = sqrtf(stats.variance);
    
    return stats;
}

// Example usage
int main(void) {
    float temp_readings[] = {22.1, 22.3, 22.0, 22.4, 22.2, 22.5, 22.1, 22.3};
    uint16_t n = sizeof(temp_readings) / sizeof(temp_readings[0]);
    
    stats_t results = calculate_stats(temp_readings, n);
    
    printf("Mean: %.4f°C\n", results.mean);
    printf("Variance: %.6f°C²\n", results.variance);
    printf("Std Dev: %.4f°C\n", results.std_deviation);
    
    return 0;
}
```

---

## Properties of Variance and Standard Deviation

### 1. **Non-negative**
```
Variance ≥ 0 and Standard Deviation ≥ 0
```
They can never be negative (squared values are always positive).

### 2. **Zero only for constant data**
```
If all values are identical: σ = 0
```

### 3. **Affected by outliers**
Large deviations are squared, so outliers have significant impact.

### 4. **Units**
- Variance has squared units (°C², g², etc.)
- Standard deviation has original units (°C, g, etc.)

### 5. **Additive for independent variables**
```
Var(X + Y) = Var(X) + Var(Y)  (if X and Y are independent)
```

---

## Coefficient of Variation (CV)

Sometimes we want to compare variability between datasets with different units or scales. The **Coefficient of Variation** is a normalized measure:

```
CV = (s / x̄) × 100%
```

### Example:
- Temperature sensor: s = 0.168°C, x̄ = 22.24°C
  ```
  CV = (0.168 / 22.24) × 100% = 0.76%
  ```

- Accelerometer: s = 0.0158g, x̄ = 0.005g
  ```
  CV = (0.0158 / 0.005) × 100% = 316%
  ```

The accelerometer has much higher relative variability (high CV) because the mean is close to zero.

---

## Practical Applications in Embedded Systems

### 1. **Noise Characterization**

```python
def characterize_sensor_noise(readings):
    """Determine sensor noise characteristics"""
    stats = calculate_variance_std(readings)
    
    # Typical noise threshold: mean ± 3σ (99.7% of data)
    noise_threshold = 3 * stats['std_deviation']
    
    return {
        'noise_floor': stats['std_deviation'],
        'detection_threshold': noise_threshold,
        'snr_estimate': stats['mean'] / stats['std_deviation']
    }

# At-rest accelerometer readings
accel_rest = [0.02, -0.01, 0.03, 0.00, 0.01, -0.02, 0.02, 0.01, -0.01, 0.00]
noise_profile = characterize_sensor_noise(accel_rest)

print(f"Noise floor: ±{noise_profile['noise_floor']:.4f}g")
print(f"Detection threshold: {noise_profile['detection_threshold']:.4f}g")
```

### 2. **Adaptive Sampling**

```c
/**
 * Adjust sampling rate based on signal variance
 * High variance = need more samples
 * Low variance = can reduce sampling
 */
uint16_t adaptive_sample_rate(stats_t *stats, uint16_t base_rate) {
    float variance_ratio = stats->variance / REFERENCE_VARIANCE;
    
    if (variance_ratio > 2.0f) {
        // High variability - increase sampling
        return base_rate * 2;
    } else if (variance_ratio < 0.5f) {
        // Low variability - reduce sampling to save power
        return base_rate / 2;
    }
    
    return base_rate;
}
```

### 3. **Outlier Detection**

```python
def detect_outliers(data, threshold=3):
    """
    Detect outliers using standard deviation method
    
    Parameters:
    data: sensor readings
    threshold: number of standard deviations (typically 2-3)
    
    Returns:
    list of (index, value) tuples for outliers
    """
    stats = calculate_variance_std(data)
    outliers = []
    
    for i, value in enumerate(data):
        z_score = abs(value - stats['mean']) / stats['std_deviation']
        if z_score > threshold:
            outliers.append((i, value, z_score))
    
    return outliers

# Example with one anomalous reading
pressure_data = [1013, 1015, 1012, 1014, 1050, 1013, 1014]  # 1050 is outlier
outliers = detect_outliers(pressure_data)

for idx, value, z_score in outliers:
    print(f"Outlier at index {idx}: {value} (z-score: {z_score:.2f})")
```

---

## The 68-95-99.7 Rule (Empirical Rule)

For **normally distributed data**, standard deviation tells us:

- **68%** of data falls within ±1σ of the mean
- **95%** of data falls within ±2σ of the mean
- **99.7%** of data falls within ±3σ of the mean

This is extremely useful for setting thresholds in embedded systems.

### Example: Motion Detection

```c
#define SIGMA_MULTIPLIER 3.0f

typedef struct {
    float mean;
    float std_dev;
    float threshold;
} motion_detector_t;

bool detect_motion(motion_detector_t *detector, float current_reading) {
    float deviation = fabsf(current_reading - detector->mean);
    
    // Motion detected if reading exceeds 3σ threshold
    if (deviation > detector->threshold) {
        return true;  // Motion detected
    }
    
    return false;  // No significant motion
}

// Initialization
motion_detector_t detector;
detector.mean = 0.005f;        // From calibration
detector.std_dev = 0.0158f;    // From noise characterization
detector.threshold = SIGMA_MULTIPLIER * detector.std_dev;  // 0.0474g
```

---

## Computational Considerations for Embedded Systems

### One-Pass Algorithm (Welford's Method)

For streaming data where you can't store all values:

```c
typedef struct {
    uint32_t count;
    float mean;
    float M2;  // Sum of squared differences
} online_stats_t;

void online_stats_init(online_stats_t *stats) {
    stats->count = 0;
    stats->mean = 0.0f;
    stats->M2 = 0.0f;
}

void online_stats_update(online_stats_t *stats, float new_value) {
    stats->count++;
    float delta = new_value - stats->mean;
    stats->mean += delta / stats->count;
    float delta2 = new_value - stats->mean;
    stats->M2 += delta * delta2;
}

float online_variance(online_stats_t *stats) {
    if (stats->count < 2) return 0.0f;
    return stats->M2 / (stats->count - 1);  // Sample variance
}

float online_std_deviation(online_stats_t *stats) {
    return sqrtf(online_variance(stats));
}
```

This approach:
- Uses minimal memory (no data array storage)
- Single pass through data
- Numerically stable
- Perfect for streaming sensor data

---

## Summary

| Concept | Formula | Units | Purpose |
|---------|---------|-------|---------|
| **Population Variance** | σ² = Σ(xᵢ - μ)² / N | Unit² | Spread in entire population |
| **Sample Variance** | s² = Σ(xᵢ - x̄)² / (n-1) | Unit² | Spread in sample (unbiased) |
| **Population Std Dev** | σ = √(σ²) | Original units | Typical deviation from mean |
| **Sample Std Dev** | s = √(s²) | Original units | Typical deviation (sample) |
| **Coefficient of Variation** | CV = (s/x̄) × 100% | Percentage | Relative variability |

### Key Takeaways

1. **Variance** quantifies spread but has squared units
2. **Standard deviation** is more interpretable (same units as data)
3. Use **(n-1)** for sample statistics (Bessel's correction)
4. **3σ rule**: ~99.7% of normal data within ±3 standard deviations
5. Essential for **noise characterization**, **outlier detection**, and **threshold setting**
6. **Welford's algorithm** enables memory-efficient online calculation

---

## Next Steps

Now that you understand variance and standard deviation, you're ready to explore:

1. **Probability distributions** (Normal, Binomial, Poisson)
2. **Z-scores** and standardization
3. **Confidence intervals**
4. **Hypothesis testing**
5. **Covariance** and **correlation** (relationships between variables)

These concepts build directly on variance and form the foundation of statistical inference and machine learning!
