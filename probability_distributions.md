# Probability Distributions

## Introduction

A **probability distribution** describes how probable different outcomes are in a random process. In embedded systems and sensor data analysis, understanding probability distributions helps us:

- **Model sensor behavior**: Characterize noise and measurement patterns
- **Make predictions**: Estimate likelihood of future readings
- **Detect anomalies**: Identify unusual patterns based on expected distributions
- **Design filters**: Create appropriate signal processing based on noise characteristics
- **Optimize algorithms**: Make decisions under uncertainty

---

## Fundamental Concepts

### Random Variable

A **random variable** is a variable whose value is determined by a random process.

**Examples in embedded systems:**
- Temperature reading from a sensor
- Number of steps detected in a minute
- Time between heartbeats
- Accelerometer noise value

### Types of Random Variables

#### Discrete Random Variables
- Can only take **specific, countable values**
- Examples: number of button presses, packet count, steps per minute

#### Continuous Random Variables
- Can take **any value within a range**
- Examples: temperature (°C), acceleration (g), voltage (V)

---

## Probability Distribution Components

### 1. Probability Mass Function (PMF) - Discrete
For discrete random variables, PMF gives the probability of each specific value:

```
P(X = x)
```

**Properties:**
- 0 ≤ P(X = x) ≤ 1 for all x
- Σ P(X = x) = 1 (sum of all probabilities equals 1)

### 2. Probability Density Function (PDF) - Continuous
For continuous random variables, PDF describes the relative likelihood of values:

```
f(x)
```

**Properties:**
- f(x) ≥ 0 for all x
- ∫ f(x)dx = 1 (area under curve equals 1)
- P(a ≤ X ≤ b) = ∫[a to b] f(x)dx

**Important:** For continuous distributions, P(X = exact value) = 0. We calculate probabilities over ranges.

### 3. Cumulative Distribution Function (CDF)
The probability that a random variable is less than or equal to a value:

```
F(x) = P(X ≤ x)
```

**Properties:**
- 0 ≤ F(x) ≤ 1
- F(x) is non-decreasing
- F(-∞) = 0, F(+∞) = 1

---

## Common Discrete Distributions

### 1. Bernoulli Distribution

**Definition:** Models a single trial with two outcomes (success/failure).

**Parameters:**
- p = probability of success
- 1-p = probability of failure

**PMF:**
```
P(X = 1) = p
P(X = 0) = 1 - p
```

**Mean:** μ = p  
**Variance:** σ² = p(1 - p)

**Embedded System Example: Button Press Detection**

A button press detection algorithm has:
- p = 0.95 (95% success rate)
- 1-p = 0.05 (5% miss rate)

```python
import numpy as np
from scipy import stats

# Bernoulli distribution
p = 0.95
bernoulli_dist = stats.bernoulli(p)

# Probability of success
print(f"P(success) = {bernoulli_dist.pmf(1)}")  # 0.95
print(f"P(failure) = {bernoulli_dist.pmf(0)}")  # 0.05

# Simulate 10 button presses
samples = bernoulli_dist.rvs(size=10)
print(f"Detections: {samples}")  # 1s and 0s
print(f"Success rate: {np.mean(samples)}")
```

---

### 2. Binomial Distribution

**Definition:** Models the number of successes in n independent Bernoulli trials.

**Parameters:**
- n = number of trials
- p = probability of success on each trial

**PMF:**
```
P(X = k) = C(n,k) × p^k × (1-p)^(n-k)

where C(n,k) = n! / (k!(n-k)!)  (combinations)
```

**Mean:** μ = np  
**Variance:** σ² = np(1 - p)

**Example: Packet Transmission**

A sensor transmits 20 packets with 90% success rate. What's the probability of exactly 18 successful transmissions?

```python
from scipy import stats
import matplotlib.pyplot as plt

n = 20  # number of packets
p = 0.90  # success probability

binomial_dist = stats.binom(n, p)

# Probability of exactly 18 successes
prob_18 = binomial_dist.pmf(18)
print(f"P(X = 18) = {prob_18:.4f}")  # 0.2852

# Probability of at least 18 successes
prob_at_least_18 = 1 - binomial_dist.cdf(17)
print(f"P(X ≥ 18) = {prob_at_least_18:.4f}")  # 0.6083

# Probability of all 20 succeeding
prob_all = binomial_dist.pmf(20)
print(f"P(X = 20) = {prob_all:.4f}")  # 0.1216

# Expected number of successes
print(f"Expected successes: {n * p}")  # 18.0

# Visualize the distribution
x = np.arange(0, n+1)
pmf_values = binomial_dist.pmf(x)

plt.figure(figsize=(10, 6))
plt.bar(x, pmf_values, alpha=0.7, edgecolor='black')
plt.axvline(n*p, color='red', linestyle='--', label=f'Mean = {n*p}')
plt.xlabel('Number of Successful Packets')
plt.ylabel('Probability')
plt.title(f'Binomial Distribution (n={n}, p={p})')
plt.grid(True, alpha=0.3)
plt.legend()
plt.show()
```

**Embedded C Implementation:**

```c
#include <math.h>

// Calculate binomial coefficient C(n,k)
uint32_t binomial_coefficient(uint16_t n, uint16_t k) {
    if (k > n) return 0;
    if (k == 0 || k == n) return 1;
    
    uint32_t result = 1;
    for (uint16_t i = 0; i < k; i++) {
        result *= (n - i);
        result /= (i + 1);
    }
    return result;
}

// Calculate binomial PMF
float binomial_pmf(uint16_t k, uint16_t n, float p) {
    uint32_t binom_coef = binomial_coefficient(n, k);
    float prob = binom_coef * powf(p, k) * powf(1 - p, n - k);
    return prob;
}

// Example: Packet transmission probability
void packet_transmission_analysis(void) {
    uint16_t n = 20;    // Total packets
    float p = 0.90f;    // Success rate
    
    // Probability of exactly 18 successful packets
    float prob_18 = binomial_pmf(18, n, p);
    printf("P(18 successes) = %.4f\n", prob_18);
    
    // Probability of at least 18 successes
    float prob_at_least_18 = 0.0f;
    for (uint16_t k = 18; k <= n; k++) {
        prob_at_least_18 += binomial_pmf(k, n, p);
    }
    printf("P(≥18 successes) = %.4f\n", prob_at_least_18);
}
```

---

### 3. Poisson Distribution

**Definition:** Models the number of events occurring in a fixed interval of time or space.

**Parameters:**
- λ (lambda) = average rate of events per interval

**PMF:**
```
P(X = k) = (λ^k × e^(-λ)) / k!
```

**Mean:** μ = λ  
**Variance:** σ² = λ

**When to use:**
- Events are independent
- Average rate is constant
- Two events cannot occur at exactly the same instant

**Example: Step Detection Events**

A pedometer detects an average of 120 steps per minute (λ = 120). What's the probability of detecting exactly 130 steps in the next minute?

```python
from scipy import stats

lambda_rate = 120  # average steps per minute

poisson_dist = stats.poisson(lambda_rate)

# Probability of exactly 130 steps
prob_130 = poisson_dist.pmf(130)
print(f"P(X = 130) = {prob_130:.4f}")  # 0.0224

# Probability of 110-130 steps
prob_range = poisson_dist.cdf(130) - poisson_dist.cdf(109)
print(f"P(110 ≤ X ≤ 130) = {prob_range:.4f}")  # 0.6894

# Probability of more than 140 steps
prob_above_140 = 1 - poisson_dist.cdf(140)
print(f"P(X > 140) = {prob_above_140:.4f}")  # 0.0334

# Expected value and standard deviation
print(f"Mean: {poisson_dist.mean()}")  # 120.0
print(f"Std Dev: {poisson_dist.std():.2f}")  # 10.95
```

**Real-world Application: Event-based Sampling**

```c
#include <math.h>

#define E_VALUE 2.71828f

// Factorial calculation (use lookup table for efficiency)
uint32_t factorial(uint8_t n) {
    uint32_t result = 1;
    for (uint8_t i = 2; i <= n; i++) {
        result *= i;
    }
    return result;
}

// Poisson PMF
float poisson_pmf(uint8_t k, float lambda) {
    float numerator = powf(lambda, k) * powf(E_VALUE, -lambda);
    float denominator = factorial(k);
    return numerator / denominator;
}

// Detect anomalous event rate
bool is_anomalous_rate(uint8_t observed_count, float expected_lambda, float threshold) {
    // Calculate probability of observing this count or more extreme
    float prob = poisson_pmf(observed_count, expected_lambda);
    
    // If probability is very low, flag as anomaly
    return (prob < threshold);
}

// Example usage
void step_detection_monitor(void) {
    float expected_rate = 120.0f;  // Expected steps per minute
    uint8_t observed = 150;         // Observed steps
    
    if (is_anomalous_rate(observed, expected_rate, 0.01f)) {
        printf("Warning: Unusual step rate detected!\n");
        // Possible running detected
    }
}
```

---

## Common Continuous Distributions

### 1. Uniform Distribution

**Definition:** All values in a range are equally likely.

**Parameters:**
- a = minimum value
- b = maximum value

**PDF:**
```
f(x) = 1/(b-a)  for a ≤ x ≤ b
f(x) = 0        otherwise
```

**Mean:** μ = (a + b) / 2  
**Variance:** σ² = (b - a)² / 12

**Example: ADC Quantization Noise**

An ADC with uniform quantization noise between -0.5 and +0.5 LSB:

```python
from scipy import stats

a, b = -0.5, 0.5
uniform_dist = stats.uniform(loc=a, scale=b-a)

# PDF at any point in range
print(f"PDF value: {uniform_dist.pdf(0.2)}")  # 1.0 (constant)

# Probability within range
prob = uniform_dist.cdf(0.25) - uniform_dist.cdf(-0.25)
print(f"P(-0.25 ≤ X ≤ 0.25) = {prob:.2f}")  # 0.50

# Mean and variance
print(f"Mean: {uniform_dist.mean()}")  # 0.0
print(f"Variance: {uniform_dist.var():.4f}")  # 0.0833
```

---

### 2. Exponential Distribution

**Definition:** Models the time between events in a Poisson process.

**Parameters:**
- λ = rate parameter (events per unit time)

**PDF:**
```
f(x) = λ × e^(-λx)  for x ≥ 0
```

**Mean:** μ = 1/λ  
**Variance:** σ² = 1/λ²

**Memoryless property:** P(X > s+t | X > s) = P(X > t)

**Example: Sensor Failure Time**

A sensor has a failure rate of 0.001 failures per hour (λ = 0.001).

```python
from scipy import stats

lambda_rate = 0.001  # failures per hour
exp_dist = stats.expon(scale=1/lambda_rate)

# Mean time to failure
print(f"MTTF: {exp_dist.mean():.0f} hours")  # 1000 hours

# Probability of failure within 500 hours
prob_500 = exp_dist.cdf(500)
print(f"P(failure ≤ 500h) = {prob_500:.4f}")  # 0.3935

# Probability of lasting more than 1500 hours
prob_1500 = 1 - exp_dist.cdf(1500)
print(f"P(survival > 1500h) = {prob_1500:.4f}")  # 0.2231
```

**Application: Battery Life Prediction**

```c
#include <math.h>

#define E_VALUE 2.71828f

// Exponential CDF
float exponential_cdf(float x, float lambda) {
    return 1.0f - powf(E_VALUE, -lambda * x);
}

// Probability of component failure before time t
float failure_probability(float time_hours, float failure_rate) {
    return exponential_cdf(time_hours, failure_rate);
}

// Battery life estimation
void battery_life_analysis(void) {
    float failure_rate = 0.001f;  // per hour
    float target_hours = 1000.0f;
    
    float failure_prob = failure_probability(target_hours, failure_rate);
    float survival_prob = 1.0f - failure_prob;
    
    printf("Probability of lasting 1000h: %.2f%%\n", survival_prob * 100);
}
```

---

### 3. Normal (Gaussian) Distribution

**Definition:** The most important distribution in statistics. Symmetric, bell-shaped curve.

**Parameters:**
- μ = mean (center of distribution)
- σ = standard deviation (spread)

**PDF:**
```
f(x) = (1/(σ√(2π))) × e^(-(x-μ)²/(2σ²))
```

**Mean:** μ  
**Variance:** σ²

**Properties:**
- Symmetric around mean
- 68% of data within μ ± 1σ
- 95% of data within μ ± 2σ
- 99.7% of data within μ ± 3σ

**Example: Temperature Sensor Noise**

Temperature sensor with mean = 25°C, σ = 0.5°C:

```python
from scipy import stats
import numpy as np
import matplotlib.pyplot as plt

mu = 25.0    # mean temperature
sigma = 0.5  # standard deviation

normal_dist = stats.norm(loc=mu, scale=sigma)

# Probability within range
prob_24_26 = normal_dist.cdf(26) - normal_dist.cdf(24)
print(f"P(24 ≤ T ≤ 26) = {prob_24_26:.4f}")  # 0.9545 (±2σ)

# Probability above 26°C
prob_above_26 = 1 - normal_dist.cdf(26)
print(f"P(T > 26) = {prob_above_26:.4f}")  # 0.0228

# 95th percentile (temperature exceeded only 5% of time)
temp_95 = normal_dist.ppf(0.95)
print(f"95th percentile: {temp_95:.2f}°C")  # 25.82°C

# Generate sample data
samples = normal_dist.rvs(size=1000)

# Visualize
plt.figure(figsize=(12, 5))

# Histogram and PDF
plt.subplot(1, 2, 1)
plt.hist(samples, bins=30, density=True, alpha=0.7, edgecolor='black')
x = np.linspace(23, 27, 100)
plt.plot(x, normal_dist.pdf(x), 'r-', linewidth=2, label='PDF')
plt.axvline(mu, color='green', linestyle='--', label=f'μ = {mu}')
plt.axvline(mu + sigma, color='orange', linestyle=':', label=f'μ + σ')
plt.axvline(mu - sigma, color='orange', linestyle=':')
plt.xlabel('Temperature (°C)')
plt.ylabel('Density')
plt.title('Normal Distribution - Temperature Sensor')
plt.legend()
plt.grid(True, alpha=0.3)

# CDF
plt.subplot(1, 2, 2)
plt.plot(x, normal_dist.cdf(x), 'b-', linewidth=2)
plt.axhline(0.5, color='green', linestyle='--', alpha=0.5)
plt.axvline(mu, color='green', linestyle='--', alpha=0.5)
plt.xlabel('Temperature (°C)')
plt.ylabel('Cumulative Probability')
plt.title('Cumulative Distribution Function')
plt.grid(True, alpha=0.3)

plt.tight_layout()
plt.show()
```

**Z-Score Transformation (Standardization)**

Convert any normal distribution to **standard normal** (μ=0, σ=1):

```
z = (x - μ) / σ
```

```python
# Z-score example
temperature = 26.5
z_score = (temperature - mu) / sigma
print(f"Temperature {temperature}°C has z-score: {z_score}")  # 3.0

# Using standard normal
std_normal = stats.norm(0, 1)
prob = 1 - std_normal.cdf(z_score)
print(f"Probability T > {temperature}: {prob:.4f}")  # 0.0013
```

**Embedded Implementation: Normal Distribution Check**

```c
#include <math.h>

#define PI 3.14159f
#define SQRT_2PI 2.50663f

// Normal PDF
float normal_pdf(float x, float mu, float sigma) {
    float exponent = -0.5f * powf((x - mu) / sigma, 2);
    return (1.0f / (sigma * SQRT_2PI)) * expf(exponent);
}

// Check if value is within acceptable range (±3σ)
bool is_within_normal_range(float value, float mean, float std_dev) {
    float z_score = fabsf((value - mean) / std_dev);
    return (z_score <= 3.0f);  // 99.7% confidence
}

// Temperature sensor validation
typedef struct {
    float mean;
    float std_dev;
    float current_reading;
} temp_sensor_t;

bool validate_temperature_reading(temp_sensor_t *sensor) {
    if (!is_within_normal_range(sensor->current_reading, 
                                 sensor->mean, 
                                 sensor->std_dev)) {
        // Reading is >3σ from mean - likely error or extreme event
        return false;
    }
    return true;
}

// Example usage
void sensor_monitoring(void) {
    temp_sensor_t sensor = {
        .mean = 25.0f,
        .std_dev = 0.5f,
        .current_reading = 27.0f  // 4σ away!
    };
    
    if (!validate_temperature_reading(&sensor)) {
        printf("Warning: Abnormal temperature reading!\n");
        // Trigger error handling or re-read
    }
}
```

---

## Central Limit Theorem (CLT)

**Statement:** The sampling distribution of the mean approaches a normal distribution as sample size increases, **regardless of the original distribution**.

**Why it matters:**
- Justifies using normal distribution for many real-world phenomena
- Enables confidence intervals and hypothesis testing
- Explains why sensor averages are normally distributed

**Example: Averaging Sensor Readings**

```python
from scipy import stats
import numpy as np
import matplotlib.pyplot as plt

# Original distribution: Uniform (NOT normal)
original_dist = stats.uniform(loc=0, scale=10)

# Function to calculate sample means
def sample_means(dist, sample_size, num_samples):
    means = []
    for _ in range(num_samples):
        sample = dist.rvs(size=sample_size)
        means.append(np.mean(sample))
    return means

# Different sample sizes
sample_sizes = [2, 5, 30, 100]
num_samples = 1000

fig, axes = plt.subplots(2, 2, figsize=(12, 10))
axes = axes.ravel()

for idx, n in enumerate(sample_sizes):
    means = sample_means(original_dist, n, num_samples)
    
    axes[idx].hist(means, bins=30, density=True, alpha=0.7, edgecolor='black')
    axes[idx].set_title(f'Sample Size n = {n}')
    axes[idx].set_xlabel('Sample Mean')
    axes[idx].set_ylabel('Density')
    axes[idx].grid(True, alpha=0.3)
    
    # Overlay normal distribution
    mu_theory = original_dist.mean()
    sigma_theory = original_dist.std() / np.sqrt(n)
    x = np.linspace(min(means), max(means), 100)
    axes[idx].plot(x, stats.norm(mu_theory, sigma_theory).pdf(x), 
                   'r-', linewidth=2, label='Theoretical Normal')
    axes[idx].legend()

plt.suptitle('Central Limit Theorem: Distribution of Sample Means', fontsize=14)
plt.tight_layout()
plt.show()
```

**Practical Application: Noise Reduction**

```c
#define AVERAGING_WINDOW 16  // Must be power of 2 for efficiency

typedef struct {
    float readings[AVERAGING_WINDOW];
    uint8_t index;
    bool buffer_full;
} sensor_averager_t;

void averager_init(sensor_averager_t *avg) {
    avg->index = 0;
    avg->buffer_full = false;
    for (uint8_t i = 0; i < AVERAGING_WINDOW; i++) {
        avg->readings[i] = 0.0f;
    }
}

void averager_add(sensor_averager_t *avg, float new_reading) {
    avg->readings[avg->index] = new_reading;
    avg->index = (avg->index + 1) % AVERAGING_WINDOW;
    
    if (avg->index == 0) {
        avg->buffer_full = true;
    }
}

float averager_get_mean(sensor_averager_t *avg) {
    float sum = 0.0f;
    uint8_t count = avg->buffer_full ? AVERAGING_WINDOW : avg->index;
    
    for (uint8_t i = 0; i < count; i++) {
        sum += avg->readings[i];
    }
    
    return sum / count;
}

// Thanks to CLT, the averaged value has reduced variance:
// σ_mean = σ_original / √n
// For n=16: σ_mean = σ_original / 4 (75% noise reduction!)
```

---

## Choosing the Right Distribution

| Scenario | Distribution | Example |
|----------|-------------|---------|
| Binary outcome (yes/no) | **Bernoulli** | Button pressed/not pressed |
| Count of successes in n trials | **Binomial** | Successful packet transmissions |
| Count of events in time/space | **Poisson** | Steps per minute, errors per hour |
| All values equally likely | **Uniform** | ADC quantization noise |
| Time between events | **Exponential** | Time to component failure |
| Continuous measurements with noise | **Normal** | Temperature, accelerometer readings |
| Averaged measurements | **Normal** (CLT) | Mean of sensor readings |

---

## Practical Workflow for Embedded Systems

### 1. Data Collection
```python
# Collect sensor data
import numpy as np

sensor_readings = []
for i in range(1000):
    reading = read_sensor()  # Your sensor read function
    sensor_readings.append(reading)

data = np.array(sensor_readings)
```

### 2. Exploratory Analysis
```python
import matplotlib.pyplot as plt

# Visualize data
plt.figure(figsize=(12, 4))

plt.subplot(1, 3, 1)
plt.plot(data)
plt.title('Time Series')
plt.xlabel('Sample')
plt.ylabel('Value')

plt.subplot(1, 3, 2)
plt.hist(data, bins=30, edgecolor='black')
plt.title('Histogram')
plt.xlabel('Value')
plt.ylabel('Frequency')

plt.subplot(1, 3, 3)
from scipy import stats
stats.probplot(data, dist="norm", plot=plt)
plt.title('Q-Q Plot (Normal)')

plt.tight_layout()
plt.show()
```

### 3. Fit Distribution
```python
# Fit normal distribution
mu, sigma = stats.norm.fit(data)
print(f"Fitted parameters: μ={mu:.4f}, σ={sigma:.4f}")

# Goodness of fit test
statistic, p_value = stats.kstest(data, 'norm', args=(mu, sigma))
print(f"KS test p-value: {p_value:.4f}")

if p_value > 0.05:
    print("Data appears normally distributed")
else:
    print("Data may not be normally distributed")
```

### 4. Use in Algorithm
```python
# Set threshold based on distribution
threshold = mu + 3 * sigma  # 99.7% confidence

def detect_anomaly(reading):
    if abs(reading - mu) > 3 * sigma:
        return True  # Anomaly detected
    return False
```

---

## Summary Table

| Distribution | Type | Parameters | Mean | Variance | Use Case |
|-------------|------|------------|------|----------|----------|
| **Bernoulli** | Discrete | p | p | p(1-p) | Single binary trial |
| **Binomial** | Discrete | n, p | np | np(1-p) | Count of successes |
| **Poisson** | Discrete | λ | λ | λ | Count of events |
| **Uniform** | Continuous | a, b | (a+b)/2 | (b-a)²/12 | Equal probability |
| **Exponential** | Continuous | λ | 1/λ | 1/λ² | Time between events |
| **Normal** | Continuous | μ, σ | μ | σ² | Natural measurements |

---

## Key Takeaways

1. **Probability distributions** model random processes mathematically
2. **Discrete distributions** (Bernoulli, Binomial, Poisson) for countable outcomes
3. **Continuous distributions** (Uniform, Exponential, Normal) for measured values
4. **Normal distribution** is most common due to Central Limit Theorem
5. Use **68-95-99.7 rule** for quick threshold setting
6. **Fit distributions to data** to characterize sensor behavior
7. **Distributions enable prediction** and anomaly detection

---

## Next Steps

Building on probability distributions, you're ready to explore:

1. **Hypothesis Testing**: Make decisions using statistical evidence
2. **Confidence Intervals**: Estimate population parameters from samples
3. **Correlation and Covariance**: Analyze relationships between variables
4. **Regression Analysis**: Model relationships and make predictions
5. **Bayesian Inference**: Update beliefs with new evidence

These concepts form the foundation for machine learning algorithms in embedded systems!
