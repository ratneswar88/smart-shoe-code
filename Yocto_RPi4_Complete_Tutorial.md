# Complete Yocto Tutorial for Raspberry Pi 4
## From Setup to Custom Applications and Drivers

---

## Table of Contents
1. [Part 1: Environment Setup](#part-1-environment-setup)
2. [Part 2: Basic Yocto Build](#part-2-basic-yocto-build)
3. [Part 3: Custom Layer Creation](#part-3-custom-layer-creation)
4. [Part 4: Custom Applications](#part-4-custom-applications)
5. [Part 5: Custom Kernel Drivers](#part-5-custom-kernel-drivers)
6. [Part 6: Advanced Topics](#part-6-advanced-topics)

---

## Part 1: Environment Setup

### Host System Requirements

**Minimum Hardware:**
- 50GB free disk space (100GB+ recommended)
- 8GB RAM minimum (16GB+ recommended)
- Fast CPU (builds take time!)

**Supported Host OS:**
- Ubuntu 20.04 LTS or 22.04 LTS (recommended)
- Fedora, OpenSUSE, Debian also supported

### Installing Dependencies

**For Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
    debianutils iputils-ping python3-git python3-jinja2 libegl1-mesa \
    libsdl1.2-dev python3-subunit mesa-common-dev zstd liblz4-tool \
    file locales libacl1
```

**Set locale (important!):**
```bash
sudo locale-gen en_US.UTF-8
```

### Workspace Setup

```bash
# Create workspace directory
mkdir -p ~/yocto-rpi4
cd ~/yocto-rpi4

# This will be our main working directory
```

---

## Part 2: Basic Yocto Build

### Step 1: Download Yocto and Raspberry Pi Layer

```bash
cd ~/yocto-rpi4

# Clone Poky (Yocto reference distribution) - Scarthgap LTS release
git clone -b scarthgap git://git.yoctoproject.org/poky.git
cd poky

# Clone meta-raspberrypi layer
git clone -b scarthgap https://github.com/agherzan/meta-raspberrypi.git

# Clone meta-openembedded (dependency for many packages)
git clone -b scarthgap https://github.com/openembedded/meta-openembedded.git
```

### Step 2: Initialize Build Environment

```bash
cd ~/yocto-rpi4/poky

# Source the build environment script
source oe-init-build-env build-rpi4

# You're now in ~/yocto-rpi4/poky/build-rpi4
```

### Step 3: Configure Build

**Edit `conf/bblayers.conf`:**
```bash
nano conf/bblayers.conf
```

Add these layers to BBLAYERS:
```bitbake
BBLAYERS ?= " \
  /home/YOUR_USERNAME/yocto-rpi4/poky/meta \
  /home/YOUR_USERNAME/yocto-rpi4/poky/meta-poky \
  /home/YOUR_USERNAME/yocto-rpi4/poky/meta-yocto-bsp \
  /home/YOUR_USERNAME/yocto-rpi4/poky/meta-raspberrypi \
  /home/YOUR_USERNAME/yocto-rpi4/poky/meta-openembedded/meta-oe \
  /home/YOUR_USERNAME/yocto-rpi4/poky/meta-openembedded/meta-python \
  /home/YOUR_USERNAME/yocto-rpi4/poky/meta-openembedded/meta-networking \
  "
```

**Edit `conf/local.conf`:**
```bash
nano conf/local.conf
```

Add/modify these settings:
```bitbake
# Machine selection
MACHINE = "raspberrypi4-64"

# Enable UART for serial console
ENABLE_UART = "1"

# Add some useful features
DISTRO_FEATURES:append = " systemd wifi bluetooth"
VIRTUAL-RUNTIME_init_manager = "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED = "sysvinit"
VIRTUAL-RUNTIME_initscripts = ""

# Enable SSH server
IMAGE_FEATURES += "ssh-server-dropbear"

# Add development tools (optional, but helpful)
EXTRA_IMAGE_FEATURES += "tools-debug tools-sdk dev-pkgs"

# Optimize build (use all CPU cores)
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"

# Enable package management
PACKAGE_CLASSES = "package_rpm"
```

### Step 4: Build Your First Image

```bash
# Build a minimal console image (takes 2-4 hours first time)
bitbake core-image-base

# Or build a more full-featured image
# bitbake core-image-full-cmdline
```

**Monitor progress:**
- Watch the terminal for progress
- Builds are incremental - subsequent builds are much faster
- Check `tmp/log/cooker/` for detailed logs if errors occur

### Step 5: Flash to SD Card

After build completes, find your image:
```bash
ls tmp/deploy/images/raspberrypi4-64/
```

**Flash to SD card (Linux):**
```bash
# Find your SD card device (be careful!)
lsblk

# Uncompress and flash (replace /dev/sdX with your SD card)
sudo bmaptool copy \
    tmp/deploy/images/raspberrypi4-64/core-image-base-raspberrypi4-64.rootfs.wic.bz2 \
    /dev/sdX

# Or use dd:
bunzip2 -c tmp/deploy/images/raspberrypi4-64/core-image-base-raspberrypi4-64.rootfs.wic.bz2 | \
    sudo dd of=/dev/sdX bs=4M status=progress && sync
```

### Step 6: Boot and Connect

1. Insert SD card into Raspberry Pi 4
2. Connect Ethernet cable
3. Power on

**Find IP address:**
- Check your router
- Or connect via serial UART (GPIO 14/15)

**SSH into device:**
```bash
ssh root@<raspberry-pi-ip>
# Default: no password for root
```

---

## Part 3: Custom Layer Creation

### Understanding Layers

Layers are organizational units in Yocto:
- **meta-poky**: Core Yocto layer
- **meta-raspberrypi**: Board support package (BSP)
- **meta-oe**: Additional recipes
- **meta-YOUR-LAYER**: Your custom layer

### Create Custom Layer

```bash
cd ~/yocto-rpi4/poky

# Create custom layer
bitbake-layers create-layer meta-roy
bitbake-layers add-layer meta-roy

# Layer structure created:
# meta-roy/
# ├── conf/
# │   └── layer.conf
# ├── COPYING.MIT
# ├── README
# └── recipes-example/
#     └── example/
#         └── example_0.1.bb
```

### Configure Layer

**Edit `meta-roy/conf/layer.conf`:**
```bash
nano meta-roy/conf/layer.conf
```

```bitbake
# We have a conf and classes directory, add to BBPATH
BBPATH .= ":${LAYERDIR}"

# We have recipes-* directories, add to BBFILES
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "meta-roy"
BBFILE_PATTERN_meta-roy = "^${LAYERDIR}/"
BBFILE_PRIORITY_meta-roy = "6"

LAYERDEPENDS_meta-roy = "core"
LAYERSERIES_COMPAT_meta-roy = "scarthgap"
```

---

## Part 4: Custom Applications

### Application 1: Hello World C Application

**Create directory structure:**
```bash
cd ~/yocto-rpi4/poky/meta-roy
mkdir -p recipes-apps/hello-world/files
```

**Create source file** `recipes-apps/hello-world/files/hello.c`:
```c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[])
{
    printf("Hello from Yocto on Raspberry Pi 4!\n");
    printf("Built by: Roy\n");
    
    if (argc > 1) {
        printf("Arguments: ");
        for (int i = 1; i < argc; i++) {
            printf("%s ", argv[i]);
        }
        printf("\n");
    }
    
    return 0;
}
```

**Create Makefile** `recipes-apps/hello-world/files/Makefile`:
```makefile
CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -O2
TARGET = hello

all: $(TARGET)

$(TARGET): hello.c
	$(CC) $(CFLAGS) -o $(TARGET) hello.c

install:
	install -d $(DESTDIR)$(bindir)
	install -m 0755 $(TARGET) $(DESTDIR)$(bindir)

clean:
	rm -f $(TARGET) *.o
```

**Create recipe** `recipes-apps/hello-world/hello-world_1.0.bb`:
```bitbake
SUMMARY = "Simple Hello World application"
DESCRIPTION = "A basic C application for Yocto testing"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://hello.c \
           file://Makefile \
          "

S = "${WORKDIR}"

do_compile() {
    oe_runmake
}

do_install() {
    oe_runmake install DESTDIR=${D} bindir=${bindir}
}
```

**Build and test:**
```bash
cd ~/yocto-rpi4/poky/build-rpi4
bitbake hello-world

# Add to your image in conf/local.conf:
# IMAGE_INSTALL:append = " hello-world"

# Rebuild image
bitbake core-image-base
```

### Application 2: Python Application with systemd Service

**Create directory:**
```bash
cd ~/yocto-rpi4/poky/meta-roy
mkdir -p recipes-apps/sensor-logger/files
```

**Create Python script** `recipes-apps/sensor-logger/files/sensor_logger.py`:
```python
#!/usr/bin/env python3

import time
import sys
from datetime import datetime

def log_message(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {msg}")
    sys.stdout.flush()

def main():
    log_message("Sensor Logger Service Started")
    
    counter = 0
    while True:
        # Simulate sensor reading
        log_message(f"Reading sensor data... (count: {counter})")
        counter += 1
        time.sleep(10)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log_message("Service stopped by user")
    except Exception as e:
        log_message(f"Error: {e}")
```

**Create systemd service** `recipes-apps/sensor-logger/files/sensor-logger.service`:
```ini
[Unit]
Description=Sensor Logger Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/sensor_logger.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Create recipe** `recipes-apps/sensor-logger/sensor-logger_1.0.bb`:
```bitbake
SUMMARY = "Python sensor logging daemon"
DESCRIPTION = "A Python service that logs sensor data with systemd"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://sensor_logger.py \
           file://sensor-logger.service \
          "

S = "${WORKDIR}"

RDEPENDS:${PN} = "python3-core"

inherit systemd

SYSTEMD_SERVICE:${PN} = "sensor-logger.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    # Install Python script
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/sensor_logger.py ${D}${bindir}/
    
    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/sensor-logger.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${systemd_system_unitdir}/sensor-logger.service"
```

### Application 3: Configuration Tool (Shell Script)

**Create directory:**
```bash
cd ~/yocto-rpi4/poky/meta-roy
mkdir -p recipes-apps/rpi-config/files
```

**Create script** `recipes-apps/rpi-config/files/rpi-config.sh`:
```bash
#!/bin/bash

# Raspberry Pi Configuration Tool

BOLD='\033[1m'
NC='\033[0m' # No Color

show_menu() {
    clear
    echo -e "${BOLD}=== Raspberry Pi Configuration Tool ===${NC}"
    echo ""
    echo "1. Show system info"
    echo "2. Show network status"
    echo "3. Show CPU temperature"
    echo "4. Show memory usage"
    echo "5. Show disk usage"
    echo "6. List GPIO exports"
    echo "7. Exit"
    echo ""
    read -p "Select option: " choice
}

show_system_info() {
    echo -e "${BOLD}System Information:${NC}"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo ""
    read -p "Press Enter to continue..."
}

show_network() {
    echo -e "${BOLD}Network Status:${NC}"
    ip addr show
    echo ""
    read -p "Press Enter to continue..."
}

show_temp() {
    echo -e "${BOLD}CPU Temperature:${NC}"
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        echo "Temperature: $(echo "scale=2; $temp / 1000" | bc)°C"
    else
        echo "Temperature sensor not found"
    fi
    echo ""
    read -p "Press Enter to continue..."
}

show_memory() {
    echo -e "${BOLD}Memory Usage:${NC}"
    free -h
    echo ""
    read -p "Press Enter to continue..."
}

show_disk() {
    echo -e "${BOLD}Disk Usage:${NC}"
    df -h
    echo ""
    read -p "Press Enter to continue..."
}

show_gpio() {
    echo -e "${BOLD}GPIO Exports:${NC}"
    if [ -d /sys/class/gpio ]; then
        ls -l /sys/class/gpio | grep gpio
    else
        echo "GPIO sysfs not available"
    fi
    echo ""
    read -p "Press Enter to continue..."
}

# Main loop
while true; do
    show_menu
    case $choice in
        1) show_system_info ;;
        2) show_network ;;
        3) show_temp ;;
        4) show_memory ;;
        5) show_disk ;;
        6) show_gpio ;;
        7) exit 0 ;;
        *) echo "Invalid option" ; sleep 1 ;;
    esac
done
```

**Create recipe** `recipes-apps/rpi-config/rpi-config_1.0.bb`:
```bitbake
SUMMARY = "Raspberry Pi configuration tool"
DESCRIPTION = "Shell script utility for RPi system configuration"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://rpi-config.sh"

S = "${WORKDIR}"

RDEPENDS:${PN} = "bash bc"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/rpi-config.sh ${D}${bindir}/rpi-config
}
```

---

## Part 5: Custom Kernel Drivers

### Driver 1: Simple Character Device Driver

**Create directory:**
```bash
cd ~/yocto-rpi4/poky/meta-roy
mkdir -p recipes-kernel/chardev-driver/files
```

**Create driver** `recipes-kernel/chardev-driver/files/chardev.c`:
```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "roydev"
#define BUFFER_SIZE 1024

static dev_t dev_num;
static struct cdev c_dev;
static struct class *cl;
static char kernel_buffer[BUFFER_SIZE];
static int buffer_size = 0;

static int device_open(struct inode *inode, struct file *file)
{
    pr_info("roydev: Device opened\n");
    return 0;
}

static int device_release(struct inode *inode, struct file *file)
{
    pr_info("roydev: Device closed\n");
    return 0;
}

static ssize_t device_read(struct file *filp, char __user *buffer, 
                           size_t length, loff_t *offset)
{
    int bytes_to_read;
    
    if (*offset >= buffer_size)
        return 0;
    
    bytes_to_read = min((int)length, buffer_size - (int)*offset);
    
    if (copy_to_user(buffer, kernel_buffer + *offset, bytes_to_read))
        return -EFAULT;
    
    *offset += bytes_to_read;
    pr_info("roydev: Read %d bytes\n", bytes_to_read);
    
    return bytes_to_read;
}

static ssize_t device_write(struct file *filp, const char __user *buffer,
                            size_t length, loff_t *offset)
{
    int bytes_to_write;
    
    bytes_to_write = min((int)length, BUFFER_SIZE - 1);
    
    if (copy_from_user(kernel_buffer, buffer, bytes_to_write))
        return -EFAULT;
    
    kernel_buffer[bytes_to_write] = '\0';
    buffer_size = bytes_to_write;
    
    pr_info("roydev: Wrote %d bytes\n", bytes_to_write);
    
    return bytes_to_write;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = device_open,
    .release = device_release,
    .read = device_read,
    .write = device_write,
};

static int __init chardev_init(void)
{
    // Allocate device number
    if (alloc_chrdev_region(&dev_num, 0, 1, DEVICE_NAME) < 0) {
        pr_err("Failed to allocate device number\n");
        return -1;
    }
    
    pr_info("roydev: Device number allocated: Major=%d, Minor=%d\n",
            MAJOR(dev_num), MINOR(dev_num));
    
    // Create device class
    if ((cl = class_create(DEVICE_NAME)) == NULL) {
        unregister_chrdev_region(dev_num, 1);
        pr_err("Failed to create class\n");
        return -1;
    }
    
    // Create device file
    if (device_create(cl, NULL, dev_num, NULL, DEVICE_NAME) == NULL) {
        class_destroy(cl);
        unregister_chrdev_region(dev_num, 1);
        pr_err("Failed to create device\n");
        return -1;
    }
    
    // Initialize cdev
    cdev_init(&c_dev, &fops);
    
    // Add cdev to system
    if (cdev_add(&c_dev, dev_num, 1) == -1) {
        device_destroy(cl, dev_num);
        class_destroy(cl);
        unregister_chrdev_region(dev_num, 1);
        pr_err("Failed to add cdev\n");
        return -1;
    }
    
    pr_info("roydev: Character device registered successfully\n");
    return 0;
}

static void __exit chardev_exit(void)
{
    cdev_del(&c_dev);
    device_destroy(cl, dev_num);
    class_destroy(cl);
    unregister_chrdev_region(dev_num, 1);
    
    pr_info("roydev: Character device unregistered\n");
}

module_init(chardev_init);
module_exit(chardev_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("Simple character device driver");
MODULE_VERSION("1.0");
```

**Create Makefile** `recipes-kernel/chardev-driver/files/Makefile`:
```makefile
obj-m := chardev.o

SRC := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC) modules

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC) modules_install

clean:
	rm -f *.o *~ core .depend .*.cmd *.ko *.mod.c
	rm -f Module.markers Module.symvers modules.order
	rm -rf .tmp_versions Modules.symvers
```

**Create recipe** `recipes-kernel/chardev-driver/chardev-driver_1.0.bb`:
```bitbake
SUMMARY = "Simple character device driver"
DESCRIPTION = "Character device driver for learning kernel development"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = "file://chardev.c \
           file://Makefile \
          "

S = "${WORKDIR}"

# Automatically load module on boot
KERNEL_MODULE_AUTOLOAD += "chardev"
```

### Driver 2: GPIO LED Control Driver

**Create directory:**
```bash
cd ~/yocto-rpi4/poky/meta-roy
mkdir -p recipes-kernel/gpio-led-driver/files
```

**Create driver** `recipes-kernel/gpio-led-driver/files/gpio_led.c`:
```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/cdev.h>

#define DEVICE_NAME "gpio_led"
#define GPIO_LED 17  // GPIO17 (Pin 11)

static dev_t dev_num;
static struct cdev c_dev;
static struct class *cl;
static int led_state = 0;

static int device_open(struct inode *inode, struct file *file)
{
    pr_info("gpio_led: Device opened\n");
    return 0;
}

static int device_release(struct inode *inode, struct file *file)
{
    pr_info("gpio_led: Device closed\n");
    return 0;
}

static ssize_t device_read(struct file *filp, char __user *buffer,
                           size_t length, loff_t *offset)
{
    char msg[32];
    int len;
    
    if (*offset > 0)
        return 0;
    
    len = snprintf(msg, sizeof(msg), "LED State: %s\n", 
                   led_state ? "ON" : "OFF");
    
    if (copy_to_user(buffer, msg, len))
        return -EFAULT;
    
    *offset += len;
    return len;
}

static ssize_t device_write(struct file *filp, const char __user *buffer,
                            size_t length, loff_t *offset)
{
    char cmd[16];
    int len;
    
    len = min((int)length, (int)sizeof(cmd) - 1);
    
    if (copy_from_user(cmd, buffer, len))
        return -EFAULT;
    
    cmd[len] = '\0';
    
    if (strncmp(cmd, "on", 2) == 0 || strncmp(cmd, "1", 1) == 0) {
        gpio_set_value(GPIO_LED, 1);
        led_state = 1;
        pr_info("gpio_led: LED turned ON\n");
    } else if (strncmp(cmd, "off", 3) == 0 || strncmp(cmd, "0", 1) == 0) {
        gpio_set_value(GPIO_LED, 0);
        led_state = 0;
        pr_info("gpio_led: LED turned OFF\n");
    }
    
    return length;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = device_open,
    .release = device_release,
    .read = device_read,
    .write = device_write,
};

static int __init gpio_led_init(void)
{
    // Request GPIO
    if (!gpio_is_valid(GPIO_LED)) {
        pr_err("gpio_led: Invalid GPIO\n");
        return -ENODEV;
    }
    
    if (gpio_request(GPIO_LED, "gpio_led") < 0) {
        pr_err("gpio_led: Cannot allocate GPIO %d\n", GPIO_LED);
        return -EBUSY;
    }
    
    gpio_direction_output(GPIO_LED, 0);
    gpio_set_value(GPIO_LED, 0);
    
    // Allocate device number
    if (alloc_chrdev_region(&dev_num, 0, 1, DEVICE_NAME) < 0) {
        gpio_free(GPIO_LED);
        return -1;
    }
    
    // Create class
    if ((cl = class_create(DEVICE_NAME)) == NULL) {
        unregister_chrdev_region(dev_num, 1);
        gpio_free(GPIO_LED);
        return -1;
    }
    
    // Create device
    if (device_create(cl, NULL, dev_num, NULL, DEVICE_NAME) == NULL) {
        class_destroy(cl);
        unregister_chrdev_region(dev_num, 1);
        gpio_free(GPIO_LED);
        return -1;
    }
    
    // Initialize cdev
    cdev_init(&c_dev, &fops);
    
    if (cdev_add(&c_dev, dev_num, 1) == -1) {
        device_destroy(cl, dev_num);
        class_destroy(cl);
        unregister_chrdev_region(dev_num, 1);
        gpio_free(GPIO_LED);
        return -1;
    }
    
    pr_info("gpio_led: Driver loaded, controlling GPIO %d\n", GPIO_LED);
    return 0;
}

static void __exit gpio_led_exit(void)
{
    gpio_set_value(GPIO_LED, 0);
    gpio_free(GPIO_LED);
    
    cdev_del(&c_dev);
    device_destroy(cl, dev_num);
    class_destroy(cl);
    unregister_chrdev_region(dev_num, 1);
    
    pr_info("gpio_led: Driver unloaded\n");
}

module_init(gpio_led_init);
module_exit(gpio_led_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("GPIO LED control driver for RPi4");
MODULE_VERSION("1.0");
```

**Create Makefile** `recipes-kernel/gpio-led-driver/files/Makefile`:
```makefile
obj-m := gpio_led.o

SRC := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC) modules

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC) modules_install

clean:
	rm -f *.o *~ core .depend .*.cmd *.ko *.mod.c
	rm -f Module.markers Module.symvers modules.order
	rm -rf .tmp_versions Modules.symvers
```

**Create recipe** `recipes-kernel/gpio-led-driver/gpio-led-driver_1.0.bb`:
```bitbake
SUMMARY = "GPIO LED control driver"
DESCRIPTION = "Kernel driver for controlling LED via GPIO on RPi4"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = "file://gpio_led.c \
           file://Makefile \
          "

S = "${WORKDIR}"

KERNEL_MODULE_AUTOLOAD += "gpio_led"
```

---

## Part 6: Advanced Topics

### Custom Image Recipe

**Create** `meta-roy/recipes-core/images/roy-image.bb`:
```bitbake
SUMMARY = "Roy's custom Raspberry Pi 4 image"
DESCRIPTION = "Custom image with all applications and drivers"

LICENSE = "MIT"

inherit core-image

# Base image features
IMAGE_FEATURES += "ssh-server-dropbear"
IMAGE_FEATURES += "tools-debug"
IMAGE_FEATURES += "package-management"

# Core packages
IMAGE_INSTALL:append = " \
    kernel-modules \
    python3 \
    python3-pip \
    bash \
    vim \
    htop \
    i2c-tools \
    spitools \
    minicom \
    screen \
    git \
    cmake \
    gcc \
    make \
"

# Custom applications
IMAGE_INSTALL:append = " \
    hello-world \
    sensor-logger \
    rpi-config \
"

# Custom drivers
IMAGE_INSTALL:append = " \
    chardev-driver \
    gpio-led-driver \
"

# Networking tools
IMAGE_INSTALL:append = " \
    iproute2 \
    iputils \
    net-tools \
    openssh-sftp-server \
"

# Development tools
IMAGE_INSTALL:append = " \
    gdb \
    strace \
    valgrind \
"

# Set root password (optional, for development)
# ROOTFS_POSTPROCESS_COMMAND += "set_root_passwd;"
# set_root_passwd() {
#     sed 's%^root:[^:]*:%root:rootpassword:%' \
#         < ${IMAGE_ROOTFS}/etc/passwd \
#         > ${IMAGE_ROOTFS}/etc/passwd.new
#     mv ${IMAGE_ROOTFS}/etc/passwd.new ${IMAGE_ROOTFS}/etc/passwd
# }

# Extra space in rootfs (MB)
IMAGE_ROOTFS_EXTRA_SPACE = "500"
```

**Build custom image:**
```bash
cd ~/yocto-rpi4/poky/build-rpi4
bitbake roy-image
```

### Package Groups

**Create** `meta-roy/recipes-core/packagegroups/packagegroup-roy-dev.bb`:
```bitbake
SUMMARY = "Roy's development tools package group"
DESCRIPTION = "Collection of development tools for embedded work"

inherit packagegroup

RDEPENDS:${PN} = "\
    gcc \
    g++ \
    make \
    cmake \
    git \
    gdb \
    strace \
    valgrind \
    binutils \
    diffutils \
    file \
    coreutils \
    util-linux \
    findutils \
    grep \
    sed \
    gawk \
    tar \
    gzip \
    bzip2 \
    xz \
    vim \
    nano \
    less \
    which \
    wget \
    curl \
"
```

Use in your image:
```bitbake
IMAGE_INSTALL:append = " packagegroup-roy-dev"
```

### Generate SDK for Cross-Development

```bash
# Generate SDK
bitbake -c populate_sdk roy-image

# SDK will be in:
# tmp/deploy/sdk/

# Install SDK on development machine:
./tmp/deploy/sdk/poky-glibc-x86_64-roy-image-cortexa72-raspberrypi4-64-toolchain-*.sh

# Source SDK environment:
source /opt/poky/*/environment-setup-cortexa72-poky-linux

# Now you can cross-compile:
$CC hello.c -o hello
```

### Adding Existing Open Source Packages

**Example: Adding libgpiod**

Edit `conf/local.conf`:
```bitbake
IMAGE_INSTALL:append = " libgpiod libgpiod-tools"
```

**Example: Creating bbappend for kernel configuration**

Create `meta-roy/recipes-kernel/linux/linux-raspberrypi_%.bbappend`:
```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://custom.cfg"
```

Create `meta-roy/recipes-kernel/linux/files/custom.cfg`:
```
CONFIG_MODULES=y
CONFIG_I2C=y
CONFIG_I2C_BCM2835=y
CONFIG_SPI=y
CONFIG_SPI_BCM2835=y
CONFIG_GPIO_SYSFS=y
```

### Device Tree Overlay

**Create** `meta-roy/recipes-kernel/linux/linux-raspberrypi_%.bbappend`:
```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://custom-overlay.dts"

do_compile:append() {
    dtc -@ -I dts -O dtb -o ${B}/custom-overlay.dtbo ${WORKDIR}/custom-overlay.dts
}

do_deploy:append() {
    install -m 0644 ${B}/custom-overlay.dtbo ${DEPLOYDIR}/overlays/
}
```

---

## Testing Your Work

### Test Applications

```bash
# SSH into device
ssh root@<rpi-ip>

# Test hello-world
hello-world arg1 arg2

# Check sensor-logger service
systemctl status sensor-logger
journalctl -u sensor-logger -f

# Run rpi-config
rpi-config
```

### Test Drivers

```bash
# Load driver manually (if not auto-loaded)
modprobe chardev

# Check if loaded
lsmod | grep chardev
dmesg | grep roydev

# Test character device
echo "Hello Driver" > /dev/roydev
cat /dev/roydev

# Test GPIO LED driver
echo "on" > /dev/gpio_led
echo "off" > /dev/gpio_led
cat /dev/gpio_led
```

### Debug Tips

```bash
# View kernel messages
dmesg

# Follow kernel log
dmesg -w

# Check module info
modinfo chardev

# List devices
ls -l /dev/

# Check systemd services
systemctl list-units --type=service
```

---

## Common Commands Reference

```bash
# Source environment
cd ~/yocto-rpi4/poky
source oe-init-build-env build-rpi4

# Clean specific recipe
bitbake -c clean <recipe-name>

# Force rebuild
bitbake -c cleanall <recipe-name>
bitbake <recipe-name>

# Build single recipe
bitbake <recipe-name>

# Build image
bitbake roy-image

# List layers
bitbake-layers show-layers

# Search for recipe
bitbake-layers show-recipes | grep <name>

# Show recipe dependencies
bitbake -g <recipe-name>

# Enter devshell (debug build)
bitbake -c devshell <recipe-name>
```

---

## Directory Structure Summary

```
~/yocto-rpi4/poky/
├── build-rpi4/              # Build directory
│   ├── conf/
│   │   ├── local.conf       # Build configuration
│   │   └── bblayers.conf    # Layer configuration
│   └── tmp/
│       └── deploy/images/   # Built images
├── meta-roy/                # Custom layer
│   ├── conf/
│   │   └── layer.conf
│   ├── recipes-apps/
│   │   ├── hello-world/
│   │   ├── sensor-logger/
│   │   └── rpi-config/
│   ├── recipes-kernel/
│   │   ├── chardev-driver/
│   │   └── gpio-led-driver/
│   └── recipes-core/
│       ├── images/
│       └── packagegroups/
├── meta-raspberrypi/        # BSP layer
├── meta-openembedded/       # OE layers
└── meta/                    # Core Poky
```

---

## Troubleshooting

### Build Errors

1. **Out of disk space**: Yocto needs 50GB+
2. **Missing dependencies**: Re-run apt install command
3. **Network issues**: Check proxy settings in `local.conf`
4. **Recipe not found**: Check `bblayers.conf`

### Runtime Issues

1. **Module won't load**: Check `dmesg` for errors
2. **Device not created**: Verify major/minor numbers
3. **Permission denied**: May need udev rules
4. **Service won't start**: Check `journalctl -xe`

### Performance

1. **Slow builds**: Increase `BB_NUMBER_THREADS` and `PARALLEL_MAKE`
2. **Use shared state cache**: Set `SSTATE_DIR` in `local.conf`
3. **Use download mirror**: Set `DL_DIR` in `local.conf`

---

## Next Steps

1. Add more complex drivers (I2C, SPI)
2. Integrate with Flutter app (for your smart shoe project)
3. Add OTA update mechanism
4. Create production image with security hardening
5. Set up continuous integration for builds
6. Learn about device tree overlays for hardware configuration

---

## Resources

- Yocto Project: https://www.yoctoproject.org/
- Yocto Docs: https://docs.yoctoproject.org/
- meta-raspberrypi: https://github.com/agherzan/meta-raspberrypi
- Raspberry Pi Forums: https://forums.raspberrypi.com/
- Yocto Mailing Lists: https://lists.yoctoproject.org/

---

**Tutorial created for Roy's embedded systems learning**
