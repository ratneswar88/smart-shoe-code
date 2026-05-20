# Linux Device Driver Development with Raspberry Pi 4
## A Complete Learning Guide

## Table of Contents
1. Prerequisites and Setup
2. Understanding the Basics
3. Your First "Hello World" Driver
4. Character Device Drivers
5. GPIO Driver Development
6. Interrupt Handling
7. Platform Drivers
8. Device Tree Integration
9. Debugging Techniques
10. Advanced Topics and Next Steps

---

## 1. Prerequisites and Setup

### Hardware Requirements
- Raspberry Pi 4 (any RAM variant will work)
- MicroSD card (16GB+ recommended)
- Power supply
- Breadboard and basic electronic components (LEDs, resistors, buttons)
- USB-to-Serial adapter (optional, for debugging)

### Software Setup

#### Install Raspberry Pi OS
```bash
# Use Raspberry Pi Imager to install Raspberry Pi OS (64-bit recommended)
# Boot your Pi and update the system
sudo apt update
sudo apt upgrade -y
```

#### Install Development Tools
```bash
# Essential build tools
sudo apt install -y build-essential git bc bison flex libssl-dev

# Install kernel headers (matches your running kernel)
sudo apt install -y raspberrypi-kernel-headers

# Verify installation
ls /lib/modules/$(uname -r)/build
```

#### Set Up Your Development Environment
```bash
# Create a workspace
mkdir -p ~/driver-dev
cd ~/driver-dev

# Optional: Install a better text editor
sudo apt install -y vim  # or nano, emacs, etc.
```

---

## 2. Understanding the Basics

### What is a Device Driver?

A device driver is a kernel module that allows the operating system to communicate with hardware devices. It acts as a translator between hardware and applications.

### Types of Device Drivers

1. **Character Devices**: Stream-oriented devices (serial ports, keyboards)
2. **Block Devices**: Block-oriented devices (hard drives, SD cards)
3. **Network Devices**: Network interfaces (ethernet, WiFi)

### Kernel Space vs User Space

- **User Space**: Where applications run, protected and isolated
- **Kernel Space**: Where the kernel and drivers run, direct hardware access
- Communication happens through system calls

### Key Concepts

- **Module**: Loadable kernel code that can be inserted/removed dynamically
- **Device File**: Interface in `/dev/` for user applications to access devices
- **Major/Minor Numbers**: Identify device drivers and specific devices
- **File Operations**: Functions like open, read, write, close

---

## 3. Your First "Hello World" Driver

### Simple Kernel Module

Create `hello.c`:

```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("A simple Hello World module");
MODULE_VERSION("1.0");

static int __init hello_init(void)
{
    printk(KERN_INFO "Hello, Kernel World!\n");
    return 0;
}

static void __exit hello_exit(void)
{
    printk(KERN_INFO "Goodbye, Kernel World!\n");
}

module_init(hello_init);
module_exit(hello_exit);
```

### Create Makefile

```makefile
obj-m += hello.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
```

### Build and Test

```bash
# Compile the module
make

# Load the module
sudo insmod hello.ko

# Check kernel messages
dmesg | tail

# List loaded modules
lsmod | grep hello

# Remove the module
sudo rmmod hello

# Check messages again
dmesg | tail
```

**What You Should See:**
```
Hello, Kernel World!
Goodbye, Kernel World!
```

---

## 4. Character Device Drivers

### Basic Character Driver

Create `chardev.c`:

```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "mychardev"
#define BUF_LEN 1024

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Simple character device driver");

static int major_number;
static char message[BUF_LEN] = {0};
static int message_size = 0;

// Device open
static int dev_open(struct inode *inodep, struct file *filep)
{
    printk(KERN_INFO "mychardev: Device opened\n");
    return 0;
}

// Device read
static ssize_t dev_read(struct file *filep, char *buffer, 
                        size_t len, loff_t *offset)
{
    int bytes_read = 0;
    
    if (*offset >= message_size)
        return 0;
    
    if (*offset + len > message_size)
        len = message_size - *offset;
    
    if (copy_to_user(buffer, message + *offset, len))
        return -EFAULT;
    
    *offset += len;
    bytes_read = len;
    
    printk(KERN_INFO "mychardev: Sent %d bytes to user\n", bytes_read);
    return bytes_read;
}

// Device write
static ssize_t dev_write(struct file *filep, const char *buffer,
                         size_t len, loff_t *offset)
{
    if (len > BUF_LEN - 1)
        len = BUF_LEN - 1;
    
    if (copy_from_user(message, buffer, len))
        return -EFAULT;
    
    message[len] = '\0';
    message_size = len;
    
    printk(KERN_INFO "mychardev: Received %zu bytes from user\n", len);
    return len;
}

// Device release
static int dev_release(struct inode *inodep, struct file *filep)
{
    printk(KERN_INFO "mychardev: Device closed\n");
    return 0;
}

// File operations structure
static struct file_operations fops = {
    .open = dev_open,
    .read = dev_read,
    .write = dev_write,
    .release = dev_release,
};

// Module initialization
static int __init chardev_init(void)
{
    major_number = register_chrdev(0, DEVICE_NAME, &fops);
    
    if (major_number < 0) {
        printk(KERN_ALERT "mychardev: Failed to register major number\n");
        return major_number;
    }
    
    printk(KERN_INFO "mychardev: Registered with major number %d\n", 
           major_number);
    printk(KERN_INFO "mychardev: Create device file: mknod /dev/%s c %d 0\n",
           DEVICE_NAME, major_number);
    
    return 0;
}

// Module cleanup
static void __exit chardev_exit(void)
{
    unregister_chrdev(major_number, DEVICE_NAME);
    printk(KERN_INFO "mychardev: Unregistered\n");
}

module_init(chardev_init);
module_exit(chardev_exit);
```

### Test Your Driver

```bash
# Compile
make

# Load module
sudo insmod chardev.ko

# Check major number
dmesg | tail

# Create device file (use major number from dmesg)
sudo mknod /dev/mychardev c <major_number> 0
sudo chmod 666 /dev/mychardev

# Test writing
echo "Hello from userspace!" > /dev/mychardev

# Test reading
cat /dev/mychardev

# Cleanup
sudo rm /dev/mychardev
sudo rmmod chardev
```

---

## 5. GPIO Driver Development

### Understanding Raspberry Pi 4 GPIO

The Raspberry Pi 4 has 40 GPIO pins. We'll create a driver to control an LED.

### GPIO Character Driver

Create `gpio_driver.c`:

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio.h>
#include <linux/fs.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "mygpio"
#define GPIO_PIN 17  // Use GPIO17 (Pin 11)

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("GPIO LED control driver");

static int major_number;
static int led_state = 0;

// Device open
static int dev_open(struct inode *inodep, struct file *filep)
{
    printk(KERN_INFO "mygpio: Device opened\n");
    return 0;
}

// Device write (control LED)
static ssize_t dev_write(struct file *filep, const char *buffer,
                         size_t len, loff_t *offset)
{
    char cmd[10];
    
    if (len > 9)
        len = 9;
    
    if (copy_from_user(cmd, buffer, len))
        return -EFAULT;
    
    cmd[len] = '\0';
    
    if (strncmp(cmd, "on", 2) == 0 || cmd[0] == '1') {
        gpio_set_value(GPIO_PIN, 1);
        led_state = 1;
        printk(KERN_INFO "mygpio: LED turned ON\n");
    } else if (strncmp(cmd, "off", 3) == 0 || cmd[0] == '0') {
        gpio_set_value(GPIO_PIN, 0);
        led_state = 0;
        printk(KERN_INFO "mygpio: LED turned OFF\n");
    }
    
    return len;
}

// Device read (get LED state)
static ssize_t dev_read(struct file *filep, char *buffer,
                        size_t len, loff_t *offset)
{
    char state_str[2];
    
    if (*offset > 0)
        return 0;
    
    state_str[0] = led_state ? '1' : '0';
    state_str[1] = '\n';
    
    if (copy_to_user(buffer, state_str, 2))
        return -EFAULT;
    
    *offset += 2;
    return 2;
}

// Device release
static int dev_release(struct inode *inodep, struct file *filep)
{
    printk(KERN_INFO "mygpio: Device closed\n");
    return 0;
}

static struct file_operations fops = {
    .open = dev_open,
    .read = dev_read,
    .write = dev_write,
    .release = dev_release,
};

// Module initialization
static int __init gpio_driver_init(void)
{
    int result;
    
    // Register character device
    major_number = register_chrdev(0, DEVICE_NAME, &fops);
    if (major_number < 0) {
        printk(KERN_ALERT "mygpio: Failed to register major number\n");
        return major_number;
    }
    
    // Request GPIO pin
    if (!gpio_is_valid(GPIO_PIN)) {
        printk(KERN_ALERT "mygpio: Invalid GPIO pin\n");
        unregister_chrdev(major_number, DEVICE_NAME);
        return -ENODEV;
    }
    
    result = gpio_request(GPIO_PIN, "LED_PIN");
    if (result) {
        printk(KERN_ALERT "mygpio: Failed to request GPIO pin\n");
        unregister_chrdev(major_number, DEVICE_NAME);
        return result;
    }
    
    // Set GPIO direction to output
    gpio_direction_output(GPIO_PIN, 0);
    
    printk(KERN_INFO "mygpio: Registered with major number %d\n", major_number);
    printk(KERN_INFO "mygpio: Create device: mknod /dev/%s c %d 0\n",
           DEVICE_NAME, major_number);
    
    return 0;
}

// Module cleanup
static void __exit gpio_driver_exit(void)
{
    gpio_set_value(GPIO_PIN, 0);  // Turn off LED
    gpio_free(GPIO_PIN);
    unregister_chrdev(major_number, DEVICE_NAME);
    printk(KERN_INFO "mygpio: Unregistered\n");
}

module_init(gpio_driver_init);
module_exit(gpio_driver_exit);
```

### Hardware Setup

```
Raspberry Pi GPIO17 (Pin 11) -> LED Anode (+)
LED Cathode (-) -> 220Ω Resistor -> Ground (Pin 6 or 9)
```

### Test the GPIO Driver

```bash
# Compile
make

# Load module
sudo insmod gpio_driver.ko

# Create device file
MAJOR=$(dmesg | grep "mygpio" | grep "major number" | awk '{print $NF}')
sudo mknod /dev/mygpio c $MAJOR 0
sudo chmod 666 /dev/mygpio

# Turn LED on
echo "on" > /dev/mygpio

# Turn LED off
echo "off" > /dev/mygpio

# Check state
cat /dev/mygpio

# Cleanup
sudo rm /dev/mygpio
sudo rmmod gpio_driver
```

---

## 6. Interrupt Handling

### GPIO Button with Interrupt

Create `button_irq.c`:

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio.h>
#include <linux/interrupt.h>

#define BUTTON_GPIO 27  // GPIO27 (Pin 13)
#define LED_GPIO 17     // GPIO17 (Pin 11)

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Button interrupt driver");

static unsigned int irq_number;
static int button_press_count = 0;

// Interrupt handler
static irq_handler_t button_irq_handler(unsigned int irq, 
                                        void *dev_id, 
                                        struct pt_regs *regs)
{
    int button_state = gpio_get_value(BUTTON_GPIO);
    
    if (button_state == 0) {  // Button pressed (active low)
        button_press_count++;
        gpio_set_value(LED_GPIO, !gpio_get_value(LED_GPIO));  // Toggle LED
        printk(KERN_INFO "button_irq: Button pressed %d times\n", 
               button_press_count);
    }
    
    return (irq_handler_t) IRQ_HANDLED;
}

// Module initialization
static int __init button_irq_init(void)
{
    int result;
    
    // Setup LED GPIO
    gpio_request(LED_GPIO, "LED_PIN");
    gpio_direction_output(LED_GPIO, 0);
    
    // Setup Button GPIO
    gpio_request(BUTTON_GPIO, "BUTTON_PIN");
    gpio_direction_input(BUTTON_GPIO);
    
    // Get IRQ number for the button GPIO
    irq_number = gpio_to_irq(BUTTON_GPIO);
    printk(KERN_INFO "button_irq: IRQ number: %d\n", irq_number);
    
    // Request interrupt
    result = request_irq(irq_number,
                        (irq_handler_t) button_irq_handler,
                        IRQF_TRIGGER_FALLING,  // Trigger on falling edge
                        "button_irq_handler",
                        NULL);
    
    if (result) {
        printk(KERN_ALERT "button_irq: Failed to request IRQ\n");
        gpio_free(BUTTON_GPIO);
        gpio_free(LED_GPIO);
        return result;
    }
    
    printk(KERN_INFO "button_irq: Module loaded successfully\n");
    return 0;
}

// Module cleanup
static void __exit button_irq_exit(void)
{
    free_irq(irq_number, NULL);
    gpio_set_value(LED_GPIO, 0);
    gpio_free(BUTTON_GPIO);
    gpio_free(LED_GPIO);
    printk(KERN_INFO "button_irq: Module unloaded. Total presses: %d\n",
           button_press_count);
}

module_init(button_irq_init);
module_exit(button_irq_exit);
```

### Hardware Setup

```
Button: GPIO27 (Pin 13) -> Button -> Ground (with pull-up resistor)
LED: GPIO17 (Pin 11) -> LED -> 220Ω Resistor -> Ground
```

---

## 7. Platform Drivers

Platform drivers are used for devices that are part of the system-on-chip (SoC) rather than discoverable buses like USB or PCI.

### Simple Platform Driver

```c
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Simple platform driver");

static int my_platform_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    
    dev_info(dev, "Platform device probed\n");
    
    // Your initialization code here
    
    return 0;
}

static int my_platform_remove(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    
    dev_info(dev, "Platform device removed\n");
    
    // Your cleanup code here
    
    return 0;
}

// Device tree matching table
static const struct of_device_id my_platform_of_match[] = {
    { .compatible = "mycompany,mydevice", },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, my_platform_of_match);

static struct platform_driver my_platform_driver = {
    .probe = my_platform_probe,
    .remove = my_platform_remove,
    .driver = {
        .name = "my_platform_driver",
        .of_match_table = my_platform_of_match,
    },
};

module_platform_driver(my_platform_driver);
```

---

## 8. Device Tree Integration

The Raspberry Pi uses Device Tree to describe hardware. You can create overlays to describe your custom hardware.

### Create a Device Tree Overlay

Create `my-overlay.dts`:

```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";  // For Raspberry Pi 4
    
    fragment@0 {
        target-path = "/";
        __overlay__ {
            my_device: mydevice@0 {
                compatible = "mycompany,mydevice";
                status = "okay";
                
                led-gpios = <&gpio 17 0>;  // GPIO17 for LED
                button-gpios = <&gpio 27 1>;  // GPIO27 for button
            };
        };
    };
};
```

### Compile the Overlay

```bash
# Install device tree compiler if not already installed
sudo apt install device-tree-compiler

# Compile the overlay
dtc -@ -I dts -O dtb -o my-overlay.dtbo my-overlay.dts

# Copy to boot overlays
sudo cp my-overlay.dtbo /boot/overlays/

# Add to config.txt
echo "dtoverlay=my-overlay" | sudo tee -a /boot/config.txt

# Reboot
sudo reboot
```

---

## 9. Debugging Techniques

### Using printk

```c
// Different log levels
printk(KERN_EMERG "Emergency message\n");
printk(KERN_ALERT "Alert message\n");
printk(KERN_CRIT "Critical message\n");
printk(KERN_ERR "Error message\n");
printk(KERN_WARNING "Warning message\n");
printk(KERN_NOTICE "Notice message\n");
printk(KERN_INFO "Info message\n");
printk(KERN_DEBUG "Debug message\n");
```

### View Kernel Messages

```bash
# Real-time kernel messages
dmesg -w

# Filter by module
dmesg | grep mymodule

# Check system log
sudo tail -f /var/log/syslog
```

### Using debugfs

```c
#include <linux/debugfs.h>

static struct dentry *debug_dir;
static int debug_value = 0;

static int __init my_init(void)
{
    // Create debugfs directory
    debug_dir = debugfs_create_dir("mydriver", NULL);
    
    // Create debugfs file
    debugfs_create_u32("debug_value", 0644, debug_dir, &debug_value);
    
    return 0;
}

static void __exit my_exit(void)
{
    debugfs_remove_recursive(debug_dir);
}
```

Access via: `cat /sys/kernel/debug/mydriver/debug_value`

### Using kgdb (Kernel Debugger)

```bash
# Enable kgdb in kernel config
# Add to /boot/cmdline.txt:
kgdboc=ttyAMA0,115200 kgdbwait

# Connect via serial console or SSH
```

---

## 10. Advanced Topics and Next Steps

### Topics to Explore Further

1. **DMA (Direct Memory Access)**
   - Transfer data without CPU intervention
   - Essential for high-performance devices

2. **I2C/SPI Device Drivers**
   - Communicate with sensors and peripherals
   - Very common on Raspberry Pi

3. **USB Device Drivers**
   - More complex but widely used

4. **Power Management**
   - Suspend/resume functionality
   - Runtime PM

5. **Concurrency and Locking**
   - Spinlocks, mutexes, semaphores
   - Critical for multi-core systems

6. **Memory Management**
   - kmalloc, vmalloc, DMA buffers
   - Memory mapping

### Practice Projects

1. **I2C Temperature Sensor Driver** (BME280, DHT22)
2. **SPI Display Driver** (Nokia 5110, OLED)
3. **PWM Motor Controller**
4. **Real-time Clock (RTC) Driver**
5. **Audio Codec Driver**

### Recommended Resources

**Books:**
- "Linux Device Drivers" by Jonathan Corbet (free online)
- "Linux Kernel Development" by Robert Love
- "Essential Linux Device Drivers" by Sreekrishnan Venkateswaran

**Online Resources:**
- kernel.org/doc/html/latest/
- linux-kernel-labs.github.io
- Free Electrons training materials
- raspberrypi.org/documentation

**Communities:**
- Raspberry Pi Forums
- Stack Overflow (linux-kernel tag)
- Reddit: r/kernel, r/raspberry_pi
- Linux Kernel Mailing List (LKML)

### Best Practices

1. **Always check return values** from kernel functions
2. **Use proper locking** to prevent race conditions
3. **Clean up resources** in exit functions
4. **Test thoroughly** before deploying
5. **Follow kernel coding style** (run `checkpatch.pl`)
6. **Document your code** clearly
7. **Handle errors gracefully**
8. **Use appropriate memory allocations** (GFP_KERNEL vs GFP_ATOMIC)

### Kernel Coding Style

```bash
# Check your code style
./scripts/checkpatch.pl --no-tree -f mydriver.c

# Use proper formatting
# - Tabs (not spaces) for indentation
# - Lines <= 80 characters
# - K&R style braces
```

---

## Quick Reference Commands

```bash
# Build module
make

# Load module
sudo insmod mymodule.ko

# Unload module
sudo rmmod mymodule

# List loaded modules
lsmod

# Module information
modinfo mymodule.ko

# View kernel messages
dmesg | tail -20

# Check kernel version
uname -r

# Find kernel sources
ls /lib/modules/$(uname -r)/build
```

---

## Conclusion

Device driver development is a challenging but rewarding skill. Start with simple modules, gradually add complexity, and don't be afraid to experiment. The Raspberry Pi 4 is an excellent, affordable platform for learning kernel development.

Remember:
- Start simple and build incrementally
- Test frequently
- Read error messages carefully
- Refer to existing kernel code for examples
- Join communities and ask questions

Happy kernel hacking! 🚀
