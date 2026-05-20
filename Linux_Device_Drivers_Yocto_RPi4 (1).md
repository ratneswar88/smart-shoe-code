# Complete Linux Device Driver Development Guide
## Yocto-based Development for Raspberry Pi 4

---

## Table of Contents
1. [Part 1: Development Environment Setup](#part-1-development-environment-setup)
2. [Part 2: Basic Driver Development](#part-2-basic-driver-development)
3. [Part 3: Character Device Drivers](#part-3-character-device-drivers)
4. [Part 4: Platform Drivers](#part-4-platform-drivers)
5. [Part 5: GPIO and Hardware Control](#part-5-gpio-and-hardware-control)
6. [Part 6: Interrupt Handling](#part-6-interrupt-handling)
7. [Part 7: I2C Device Drivers](#part-7-i2c-device-drivers)
8. [Part 8: SPI Device Drivers](#part-8-spi-device-drivers)
9. [Part 9: Advanced Driver Topics](#part-9-advanced-driver-topics)
10. [Part 10: Debugging and Testing](#part-10-debugging-and-testing)

---

## Part 1: Development Environment Setup

### Yocto Build System Setup

**Install dependencies:**
```bash
sudo apt update
sudo apt install -y gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
    debianutils iputils-ping python3-git python3-jinja2 libegl1-mesa \
    libsdl1.2-dev python3-subunit mesa-common-dev zstd liblz4-tool \
    file locales libacl1
```

**Create Yocto workspace:**
```bash
mkdir -p ~/yocto-drivers
cd ~/yocto-drivers

# Clone Poky (Scarthgap LTS)
git clone -b scarthgap git://git.yoctoproject.org/poky.git
cd poky

# Clone Raspberry Pi BSP
git clone -b scarthgap https://github.com/agherzan/meta-raspberrypi.git

# Clone meta-openembedded
git clone -b scarthgap https://github.com/openembedded/meta-openembedded.git

# Initialize build environment
source oe-init-build-env build-rpi4
```

**Configure layers** in `conf/bblayers.conf`:
```bitbake
BBLAYERS ?= " \
  /home/YOUR_USERNAME/yocto-drivers/poky/meta \
  /home/YOUR_USERNAME/yocto-drivers/poky/meta-poky \
  /home/YOUR_USERNAME/yocto-drivers/poky/meta-yocto-bsp \
  /home/YOUR_USERNAME/yocto-drivers/poky/meta-raspberrypi \
  /home/YOUR_USERNAME/yocto-drivers/poky/meta-openembedded/meta-oe \
  /home/YOUR_USERNAME/yocto-drivers/poky/meta-openembedded/meta-python \
  /home/YOUR_USERNAME/yocto-drivers/poky/meta-openembedded/meta-networking \
  "
```

**Configure build** in `conf/local.conf`:
```bitbake
MACHINE = "raspberrypi4-64"
ENABLE_UART = "1"

# systemd for modern service management
DISTRO_FEATURES:append = " systemd"
VIRTUAL-RUNTIME_init_manager = "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED = "sysvinit"

# Enable development features
IMAGE_FEATURES += "ssh-server-dropbear"
EXTRA_IMAGE_FEATURES += "tools-debug tools-sdk dev-pkgs"

# Kernel development features
IMAGE_INSTALL:append = " kernel-modules kernel-devsrc"

# Build optimization
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"
```

### Create Custom Driver Layer

```bash
cd ~/yocto-drivers/poky
bitbake-layers create-layer meta-drivers
bitbake-layers add-layer meta-drivers
```

**Layer structure:**
```
meta-drivers/
├── conf/
│   └── layer.conf
├── recipes-kernel/
│   └── modules/
│       ├── simple-module/
│       ├── chardev-driver/
│       ├── platform-driver/
│       ├── gpio-driver/
│       ├── interrupt-driver/
│       ├── i2c-driver/
│       └── spi-driver/
└── recipes-support/
    └── driver-test/
```

---

## Part 2: Basic Driver Development

### Simple Kernel Module

**Create directory:**
```bash
cd ~/yocto-drivers/poky/meta-drivers
mkdir -p recipes-kernel/modules/simple-module/files
```

**Module source** `recipes-kernel/modules/simple-module/files/simple_module.c`:
```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

static int __init simple_module_init(void)
{
    pr_info("Simple Module: Hello from kernel space!\n");
    pr_info("Simple Module: Built by Roy for RPi4\n");
    return 0;
}

static void __exit simple_module_exit(void)
{
    pr_info("Simple Module: Goodbye from kernel space!\n");
}

module_init(simple_module_init);
module_exit(simple_module_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy <roy@embedded.dev>");
MODULE_DESCRIPTION("Simple kernel module for learning");
MODULE_VERSION("1.0");
```

**Makefile** `recipes-kernel/modules/simple-module/files/Makefile`:
```makefile
obj-m := simple_module.o

SRC := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC) modules

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC) modules_install

clean:
	rm -f *.o *~ core .depend .*.cmd *.ko *.mod.c *.mod
	rm -f Module.markers Module.symvers modules.order
	rm -rf .tmp_versions Modules.symvers
```

**BitBake recipe** `recipes-kernel/modules/simple-module/simple-module_1.0.bb`:
```bitbake
SUMMARY = "Simple kernel module"
DESCRIPTION = "Basic kernel module for learning driver development"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = "file://simple_module.c \
           file://Makefile \
          "

S = "${WORKDIR}"

# Module will be loaded automatically on boot
KERNEL_MODULE_AUTOLOAD += "simple_module"

# Module will be probed automatically
KERNEL_MODULE_PROBECONF += "simple_module"
```

**Build and test:**
```bash
bitbake simple-module

# Add to image in conf/local.conf:
# IMAGE_INSTALL:append = " simple-module"

bitbake core-image-base
```

---

## Part 3: Character Device Drivers

### Basic Character Device

**Create directory:**
```bash
mkdir -p recipes-kernel/modules/chardev-driver/files
```

**Driver source** `recipes-kernel/modules/chardev-driver/files/chardev.c`:
```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/mutex.h>

#define DEVICE_NAME "roychar"
#define CLASS_NAME "roy"
#define BUFFER_SIZE 1024

struct chardev_data {
    struct cdev cdev;
    dev_t dev_num;
    struct class *class;
    struct device *device;
    char *buffer;
    size_t buffer_size;
    struct mutex lock;
};

static struct chardev_data *char_data;

static int chardev_open(struct inode *inode, struct file *file)
{
    struct chardev_data *data;
    
    data = container_of(inode->i_cdev, struct chardev_data, cdev);
    file->private_data = data;
    
    pr_info("roychar: Device opened by process %d (%s)\n", 
            current->pid, current->comm);
    
    return 0;
}

static int chardev_release(struct inode *inode, struct file *file)
{
    pr_info("roychar: Device closed\n");
    return 0;
}

static ssize_t chardev_read(struct file *file, char __user *user_buffer,
                            size_t count, loff_t *offset)
{
    struct chardev_data *data = file->private_data;
    ssize_t bytes_to_read;
    ssize_t bytes_read;
    
    if (mutex_lock_interruptible(&data->lock))
        return -ERESTARTSYS;
    
    if (*offset >= data->buffer_size) {
        mutex_unlock(&data->lock);
        return 0;
    }
    
    bytes_to_read = min(count, data->buffer_size - (size_t)*offset);
    
    if (copy_to_user(user_buffer, data->buffer + *offset, bytes_to_read)) {
        mutex_unlock(&data->lock);
        return -EFAULT;
    }
    
    *offset += bytes_to_read;
    bytes_read = bytes_to_read;
    
    mutex_unlock(&data->lock);
    
    pr_info("roychar: Read %zd bytes at offset %lld\n", bytes_read, *offset);
    
    return bytes_read;
}

static ssize_t chardev_write(struct file *file, const char __user *user_buffer,
                             size_t count, loff_t *offset)
{
    struct chardev_data *data = file->private_data;
    ssize_t bytes_to_write;
    ssize_t bytes_written;
    
    if (mutex_lock_interruptible(&data->lock))
        return -ERESTARTSYS;
    
    bytes_to_write = min(count, (size_t)(BUFFER_SIZE - 1));
    
    if (copy_from_user(data->buffer, user_buffer, bytes_to_write)) {
        mutex_unlock(&data->lock);
        return -EFAULT;
    }
    
    data->buffer[bytes_to_write] = '\0';
    data->buffer_size = bytes_to_write;
    bytes_written = bytes_to_write;
    
    mutex_unlock(&data->lock);
    
    pr_info("roychar: Wrote %zd bytes: %s\n", bytes_written, data->buffer);
    
    return bytes_written;
}

static loff_t chardev_llseek(struct file *file, loff_t offset, int whence)
{
    struct chardev_data *data = file->private_data;
    loff_t new_pos;
    
    switch (whence) {
    case SEEK_SET:
        new_pos = offset;
        break;
    case SEEK_CUR:
        new_pos = file->f_pos + offset;
        break;
    case SEEK_END:
        new_pos = data->buffer_size + offset;
        break;
    default:
        return -EINVAL;
    }
    
    if (new_pos < 0 || new_pos > BUFFER_SIZE)
        return -EINVAL;
    
    file->f_pos = new_pos;
    return new_pos;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = chardev_open,
    .release = chardev_release,
    .read = chardev_read,
    .write = chardev_write,
    .llseek = chardev_llseek,
};

static int __init chardev_init(void)
{
    int ret;
    
    // Allocate device data structure
    char_data = kzalloc(sizeof(struct chardev_data), GFP_KERNEL);
    if (!char_data)
        return -ENOMEM;
    
    // Allocate buffer
    char_data->buffer = kzalloc(BUFFER_SIZE, GFP_KERNEL);
    if (!char_data->buffer) {
        kfree(char_data);
        return -ENOMEM;
    }
    
    mutex_init(&char_data->lock);
    
    // Allocate device number
    ret = alloc_chrdev_region(&char_data->dev_num, 0, 1, DEVICE_NAME);
    if (ret < 0) {
        pr_err("roychar: Failed to allocate device number\n");
        goto err_alloc;
    }
    
    pr_info("roychar: Allocated Major=%d, Minor=%d\n",
            MAJOR(char_data->dev_num), MINOR(char_data->dev_num));
    
    // Initialize cdev
    cdev_init(&char_data->cdev, &fops);
    char_data->cdev.owner = THIS_MODULE;
    
    // Add cdev to kernel
    ret = cdev_add(&char_data->cdev, char_data->dev_num, 1);
    if (ret < 0) {
        pr_err("roychar: Failed to add cdev\n");
        goto err_cdev;
    }
    
    // Create device class
    char_data->class = class_create(CLASS_NAME);
    if (IS_ERR(char_data->class)) {
        pr_err("roychar: Failed to create class\n");
        ret = PTR_ERR(char_data->class);
        goto err_class;
    }
    
    // Create device
    char_data->device = device_create(char_data->class, NULL, 
                                      char_data->dev_num, NULL, 
                                      DEVICE_NAME);
    if (IS_ERR(char_data->device)) {
        pr_err("roychar: Failed to create device\n");
        ret = PTR_ERR(char_data->device);
        goto err_device;
    }
    
    pr_info("roychar: Character device registered successfully\n");
    return 0;

err_device:
    class_destroy(char_data->class);
err_class:
    cdev_del(&char_data->cdev);
err_cdev:
    unregister_chrdev_region(char_data->dev_num, 1);
err_alloc:
    kfree(char_data->buffer);
    kfree(char_data);
    return ret;
}

static void __exit chardev_exit(void)
{
    device_destroy(char_data->class, char_data->dev_num);
    class_destroy(char_data->class);
    cdev_del(&char_data->cdev);
    unregister_chrdev_region(char_data->dev_num, 1);
    kfree(char_data->buffer);
    kfree(char_data);
    
    pr_info("roychar: Character device unregistered\n");
}

module_init(chardev_init);
module_exit(chardev_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy <roy@embedded.dev>");
MODULE_DESCRIPTION("Character device driver with proper locking");
MODULE_VERSION("1.0");
```

**Recipe** `recipes-kernel/modules/chardev-driver/chardev-driver_1.0.bb`:
```bitbake
SUMMARY = "Character device driver"
DESCRIPTION = "Full-featured character device driver for RPi4"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = "file://chardev.c \
           file://Makefile \
          "

S = "${WORKDIR}"

KERNEL_MODULE_AUTOLOAD += "chardev"
```

### Character Device with IOCTL

**Enhanced driver** `chardev_ioctl.c`:
```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/ioctl.h>

#define DEVICE_NAME "royioctl"
#define CLASS_NAME "roy"

// Define IOCTL commands
#define IOCTL_MAGIC 'R'
#define IOCTL_GET_SIZE      _IOR(IOCTL_MAGIC, 1, int)
#define IOCTL_SET_SIZE      _IOW(IOCTL_MAGIC, 2, int)
#define IOCTL_CLEAR_BUFFER  _IO(IOCTL_MAGIC, 3)
#define IOCTL_GET_INFO      _IOR(IOCTL_MAGIC, 4, struct device_info)

struct device_info {
    char name[32];
    int version;
    unsigned long flags;
};

static dev_t dev_num;
static struct cdev c_cdev;
static struct class *dev_class;
static char kernel_buffer[1024];
static size_t buffer_size = 0;

static long chardev_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    struct device_info info;
    int size;
    
    switch (cmd) {
    case IOCTL_GET_SIZE:
        size = buffer_size;
        if (copy_to_user((int __user *)arg, &size, sizeof(size)))
            return -EFAULT;
        pr_info("royioctl: GET_SIZE = %d\n", size);
        break;
        
    case IOCTL_SET_SIZE:
        if (copy_from_user(&size, (int __user *)arg, sizeof(size)))
            return -EFAULT;
        if (size < 0 || size > sizeof(kernel_buffer))
            return -EINVAL;
        buffer_size = size;
        pr_info("royioctl: SET_SIZE = %d\n", size);
        break;
        
    case IOCTL_CLEAR_BUFFER:
        memset(kernel_buffer, 0, sizeof(kernel_buffer));
        buffer_size = 0;
        pr_info("royioctl: CLEAR_BUFFER\n");
        break;
        
    case IOCTL_GET_INFO:
        strscpy(info.name, DEVICE_NAME, sizeof(info.name));
        info.version = 1;
        info.flags = 0;
        if (copy_to_user((struct device_info __user *)arg, &info, sizeof(info)))
            return -EFAULT;
        pr_info("royioctl: GET_INFO\n");
        break;
        
    default:
        return -ENOTTY;
    }
    
    return 0;
}

static int chardev_open(struct inode *inode, struct file *file)
{
    pr_info("royioctl: Device opened\n");
    return 0;
}

static int chardev_release(struct inode *inode, struct file *file)
{
    pr_info("royioctl: Device closed\n");
    return 0;
}

static ssize_t chardev_read(struct file *file, char __user *buf,
                            size_t count, loff_t *offset)
{
    size_t bytes_to_read;
    
    if (*offset >= buffer_size)
        return 0;
    
    bytes_to_read = min(count, buffer_size - (size_t)*offset);
    
    if (copy_to_user(buf, kernel_buffer + *offset, bytes_to_read))
        return -EFAULT;
    
    *offset += bytes_to_read;
    return bytes_to_read;
}

static ssize_t chardev_write(struct file *file, const char __user *buf,
                             size_t count, loff_t *offset)
{
    size_t bytes_to_write;
    
    bytes_to_write = min(count, sizeof(kernel_buffer) - 1);
    
    if (copy_from_user(kernel_buffer, buf, bytes_to_write))
        return -EFAULT;
    
    kernel_buffer[bytes_to_write] = '\0';
    buffer_size = bytes_to_write;
    
    return bytes_to_write;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = chardev_open,
    .release = chardev_release,
    .read = chardev_read,
    .write = chardev_write,
    .unlocked_ioctl = chardev_ioctl,
};

static int __init chardev_init(void)
{
    if (alloc_chrdev_region(&dev_num, 0, 1, DEVICE_NAME) < 0)
        return -1;
    
    if ((dev_class = class_create(CLASS_NAME)) == NULL) {
        unregister_chrdev_region(dev_num, 1);
        return -1;
    }
    
    if (device_create(dev_class, NULL, dev_num, NULL, DEVICE_NAME) == NULL) {
        class_destroy(dev_class);
        unregister_chrdev_region(dev_num, 1);
        return -1;
    }
    
    cdev_init(&c_cdev, &fops);
    
    if (cdev_add(&c_cdev, dev_num, 1) == -1) {
        device_destroy(dev_class, dev_num);
        class_destroy(dev_class);
        unregister_chrdev_region(dev_num, 1);
        return -1;
    }
    
    pr_info("royioctl: Device registered with IOCTL support\n");
    return 0;
}

static void __exit chardev_exit(void)
{
    cdev_del(&c_cdev);
    device_destroy(dev_class, dev_num);
    class_destroy(dev_class);
    unregister_chrdev_region(dev_num, 1);
    pr_info("royioctl: Device unregistered\n");
}

module_init(chardev_init);
module_exit(chardev_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("Character device with IOCTL");
```

**Test application** `recipes-support/driver-test/files/test_ioctl.c`:
```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <string.h>

#define IOCTL_MAGIC 'R'
#define IOCTL_GET_SIZE      _IOR(IOCTL_MAGIC, 1, int)
#define IOCTL_SET_SIZE      _IOW(IOCTL_MAGIC, 2, int)
#define IOCTL_CLEAR_BUFFER  _IO(IOCTL_MAGIC, 3)
#define IOCTL_GET_INFO      _IOR(IOCTL_MAGIC, 4, struct device_info)

struct device_info {
    char name[32];
    int version;
    unsigned long flags;
};

int main()
{
    int fd;
    int size;
    struct device_info info;
    char buffer[100];
    
    // Open device
    fd = open("/dev/royioctl", O_RDWR);
    if (fd < 0) {
        perror("Failed to open device");
        return -1;
    }
    
    // Write data
    strcpy(buffer, "Hello from userspace!");
    write(fd, buffer, strlen(buffer));
    printf("Wrote: %s\n", buffer);
    
    // Get size
    if (ioctl(fd, IOCTL_GET_SIZE, &size) == 0)
        printf("Buffer size: %d\n", size);
    
    // Get device info
    if (ioctl(fd, IOCTL_GET_INFO, &info) == 0) {
        printf("Device name: %s\n", info.name);
        printf("Version: %d\n", info.version);
    }
    
    // Read data back
    lseek(fd, 0, SEEK_SET);
    memset(buffer, 0, sizeof(buffer));
    read(fd, buffer, sizeof(buffer));
    printf("Read: %s\n", buffer);
    
    // Clear buffer
    ioctl(fd, IOCTL_CLEAR_BUFFER, NULL);
    printf("Buffer cleared\n");
    
    close(fd);
    return 0;
}
```

---

## Part 4: Platform Drivers

### Platform Device Driver

**Driver** `recipes-kernel/modules/platform-driver/files/platform_drv.c`:
```c
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/slab.h>

struct roy_platform_data {
    void __iomem *base;
    int irq;
    char name[32];
};

static int roy_platform_probe(struct platform_device *pdev)
{
    struct roy_platform_data *priv;
    struct resource *res;
    struct device *dev = &pdev->dev;
    const char *name;
    
    pr_info("roy_platform: Probing device\n");
    
    // Allocate private data
    priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
    if (!priv)
        return -ENOMEM;
    
    // Get memory resource
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    if (res) {
        priv->base = devm_ioremap_resource(dev, res);
        if (IS_ERR(priv->base))
            return PTR_ERR(priv->base);
        pr_info("roy_platform: Memory mapped at %px\n", priv->base);
    }
    
    // Get IRQ
    priv->irq = platform_get_irq(pdev, 0);
    if (priv->irq > 0)
        pr_info("roy_platform: IRQ number: %d\n", priv->irq);
    
    // Get device tree property
    if (!of_property_read_string(dev->of_node, "label", &name)) {
        strscpy(priv->name, name, sizeof(priv->name));
        pr_info("roy_platform: Device name from DT: %s\n", priv->name);
    }
    
    // Store private data
    platform_set_drvdata(pdev, priv);
    
    pr_info("roy_platform: Probe successful\n");
    return 0;
}

static int roy_platform_remove(struct platform_device *pdev)
{
    pr_info("roy_platform: Removing device\n");
    return 0;
}

static const struct of_device_id roy_platform_of_match[] = {
    { .compatible = "roy,platform-device", },
    { }
};
MODULE_DEVICE_TABLE(of, roy_platform_of_match);

static struct platform_driver roy_platform_driver = {
    .probe = roy_platform_probe,
    .remove = roy_platform_remove,
    .driver = {
        .name = "roy-platform",
        .of_match_table = roy_platform_of_match,
    },
};

module_platform_driver(roy_platform_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("Platform driver example");
MODULE_VERSION("1.0");
```

**Device Tree Overlay** `recipes-kernel/modules/platform-driver/files/roy-platform.dts`:
```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target-path = "/";
        __overlay__ {
            roy_device: roy-platform-device {
                compatible = "roy,platform-device";
                label = "Roy's Platform Device";
                status = "okay";
            };
        };
    };
};
```

---

## Part 5: GPIO and Hardware Control

### GPIO Driver with Sysfs Interface

**Driver** `recipes-kernel/modules/gpio-driver/files/gpio_drv.c`:
```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_gpio.h>

#define DRIVER_NAME "roy-gpio"

struct gpio_dev_data {
    struct platform_device *pdev;
    int gpio;
    int state;
    struct kobject *kobj;
};

static struct gpio_dev_data *gpio_data;

// Sysfs show function
static ssize_t state_show(struct kobject *kobj, struct kobj_attribute *attr,
                          char *buf)
{
    return sprintf(buf, "%d\n", gpio_data->state);
}

// Sysfs store function
static ssize_t state_store(struct kobject *kobj, struct kobj_attribute *attr,
                           const char *buf, size_t count)
{
    int val;
    
    if (kstrtoint(buf, 10, &val) < 0)
        return -EINVAL;
    
    if (val != 0 && val != 1)
        return -EINVAL;
    
    gpio_set_value(gpio_data->gpio, val);
    gpio_data->state = val;
    
    pr_info("roy-gpio: GPIO set to %d\n", val);
    
    return count;
}

// Sysfs attribute
static struct kobj_attribute state_attr = __ATTR_RW(state);

static int gpio_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    int ret;
    
    pr_info("roy-gpio: Probing GPIO driver\n");
    
    // Allocate data structure
    gpio_data = devm_kzalloc(dev, sizeof(*gpio_data), GFP_KERNEL);
    if (!gpio_data)
        return -ENOMEM;
    
    gpio_data->pdev = pdev;
    
    // Get GPIO from device tree
    gpio_data->gpio = of_get_named_gpio(dev->of_node, "gpios", 0);
    if (!gpio_is_valid(gpio_data->gpio)) {
        dev_err(dev, "Invalid GPIO\n");
        return -EINVAL;
    }
    
    pr_info("roy-gpio: Using GPIO %d\n", gpio_data->gpio);
    
    // Request GPIO
    ret = devm_gpio_request(dev, gpio_data->gpio, DRIVER_NAME);
    if (ret) {
        dev_err(dev, "Failed to request GPIO\n");
        return ret;
    }
    
    // Configure as output
    ret = gpio_direction_output(gpio_data->gpio, 0);
    if (ret) {
        dev_err(dev, "Failed to set GPIO direction\n");
        return ret;
    }
    
    // Create sysfs entry
    gpio_data->kobj = kobject_create_and_add("roy_gpio", kernel_kobj);
    if (!gpio_data->kobj)
        return -ENOMEM;
    
    ret = sysfs_create_file(gpio_data->kobj, &state_attr.attr);
    if (ret)
        kobject_put(gpio_data->kobj);
    
    platform_set_drvdata(pdev, gpio_data);
    
    pr_info("roy-gpio: Driver probed successfully\n");
    pr_info("roy-gpio: Control via: /sys/kernel/roy_gpio/state\n");
    
    return 0;
}

static int gpio_remove(struct platform_device *pdev)
{
    gpio_set_value(gpio_data->gpio, 0);
    sysfs_remove_file(gpio_data->kobj, &state_attr.attr);
    kobject_put(gpio_data->kobj);
    
    pr_info("roy-gpio: Driver removed\n");
    return 0;
}

static const struct of_device_id gpio_of_match[] = {
    { .compatible = "roy,gpio-device", },
    { }
};
MODULE_DEVICE_TABLE(of, gpio_of_match);

static struct platform_driver gpio_driver = {
    .probe = gpio_probe,
    .remove = gpio_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = gpio_of_match,
    },
};

module_platform_driver(gpio_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("GPIO driver with sysfs control");
MODULE_VERSION("1.0");
```

**Device Tree Overlay** `recipes-kernel/modules/gpio-driver/files/roy-gpio.dts`:
```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target = <&gpio>;
        __overlay__ {
            roy_gpio_pins: roy_gpio_pins {
                brcm,pins = <17>;  // GPIO17
                brcm,function = <1>;  // Output
                brcm,pull = <0>;  // No pull
            };
        };
    };
    
    fragment@1 {
        target-path = "/";
        __overlay__ {
            roy_gpio: roy-gpio-device {
                compatible = "roy,gpio-device";
                gpios = <&gpio 17 0>;
                pinctrl-names = "default";
                pinctrl-0 = <&roy_gpio_pins>;
                status = "okay";
            };
        };
    };
};
```

### Multiple GPIO Control Driver

**Driver** `gpio_multi.c`:
```c
#include <linux/module.h>
#include <linux/gpio.h>
#include <linux/platform_device.h>
#include <linux/of.h>

#define NUM_GPIOS 4

struct multi_gpio_data {
    int gpios[NUM_GPIOS];
    int num_gpios;
    struct platform_device *pdev;
};

static ssize_t gpio_show(struct device *dev, struct device_attribute *attr,
                         char *buf)
{
    struct multi_gpio_data *data = dev_get_drvdata(dev);
    int i, len = 0;
    
    for (i = 0; i < data->num_gpios; i++) {
        len += sprintf(buf + len, "GPIO%d: %d\n", 
                      data->gpios[i], 
                      gpio_get_value(data->gpios[i]));
    }
    
    return len;
}

static ssize_t gpio_store(struct device *dev, struct device_attribute *attr,
                          const char *buf, size_t count)
{
    struct multi_gpio_data *data = dev_get_drvdata(dev);
    int gpio_num, value;
    
    if (sscanf(buf, "%d %d", &gpio_num, &value) != 2)
        return -EINVAL;
    
    // Find and set the GPIO
    for (int i = 0; i < data->num_gpios; i++) {
        if (data->gpios[i] == gpio_num) {
            gpio_set_value(gpio_num, value ? 1 : 0);
            dev_info(dev, "Set GPIO %d to %d\n", gpio_num, value);
            return count;
        }
    }
    
    return -EINVAL;
}

static DEVICE_ATTR(gpios, 0664, gpio_show, gpio_store);

static int multi_gpio_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct multi_gpio_data *data;
    int ret, i;
    
    data = devm_kzalloc(dev, sizeof(*data), GFP_KERNEL);
    if (!data)
        return -ENOMEM;
    
    data->pdev = pdev;
    
    // Get GPIOs from device tree
    data->num_gpios = of_gpio_named_count(dev->of_node, "gpios");
    if (data->num_gpios > NUM_GPIOS)
        data->num_gpios = NUM_GPIOS;
    
    for (i = 0; i < data->num_gpios; i++) {
        data->gpios[i] = of_get_named_gpio(dev->of_node, "gpios", i);
        
        if (!gpio_is_valid(data->gpios[i])) {
            dev_err(dev, "Invalid GPIO %d\n", i);
            continue;
        }
        
        ret = devm_gpio_request(dev, data->gpios[i], "multi-gpio");
        if (ret) {
            dev_err(dev, "Failed to request GPIO %d\n", data->gpios[i]);
            continue;
        }
        
        gpio_direction_output(data->gpios[i], 0);
        dev_info(dev, "Configured GPIO %d\n", data->gpios[i]);
    }
    
    // Create sysfs attribute
    ret = device_create_file(dev, &dev_attr_gpios);
    if (ret)
        return ret;
    
    platform_set_drvdata(pdev, data);
    
    dev_info(dev, "Multi-GPIO driver probed with %d GPIOs\n", data->num_gpios);
    return 0;
}

static int multi_gpio_remove(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct multi_gpio_data *data = platform_get_drvdata(pdev);
    
    // Turn off all GPIOs
    for (int i = 0; i < data->num_gpios; i++)
        gpio_set_value(data->gpios[i], 0);
    
    device_remove_file(dev, &dev_attr_gpios);
    
    dev_info(dev, "Multi-GPIO driver removed\n");
    return 0;
}

static const struct of_device_id multi_gpio_of_match[] = {
    { .compatible = "roy,multi-gpio", },
    { }
};
MODULE_DEVICE_TABLE(of, multi_gpio_of_match);

static struct platform_driver multi_gpio_driver = {
    .probe = multi_gpio_probe,
    .remove = multi_gpio_remove,
    .driver = {
        .name = "multi-gpio",
        .of_match_table = multi_gpio_of_match,
    },
};

module_platform_driver(multi_gpio_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("Multiple GPIO control driver");
```

---

## Part 6: Interrupt Handling

### GPIO Interrupt Driver

**Driver** `recipes-kernel/modules/interrupt-driver/files/gpio_irq.c`:
```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio.h>
#include <linux/interrupt.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_gpio.h>
#include <linux/ktime.h>

#define DRIVER_NAME "roy-gpio-irq"

struct gpio_irq_data {
    int gpio;
    int irq;
    unsigned long irq_count;
    ktime_t last_interrupt;
    struct platform_device *pdev;
};

static struct gpio_irq_data *irq_data;

// Interrupt handler (top half)
static irqreturn_t gpio_irq_handler(int irq, void *dev_id)
{
    struct gpio_irq_data *data = (struct gpio_irq_data *)dev_id;
    
    data->irq_count++;
    data->last_interrupt = ktime_get();
    
    pr_info("roy-gpio-irq: Interrupt #%lu triggered on GPIO %d\n",
            data->irq_count, data->gpio);
    
    return IRQ_WAKE_THREAD;  // Schedule threaded handler
}

// Threaded interrupt handler (bottom half)
static irqreturn_t gpio_irq_thread(int irq, void *dev_id)
{
    struct gpio_irq_data *data = (struct gpio_irq_data *)dev_id;
    int gpio_val;
    
    // Read GPIO value
    gpio_val = gpio_get_value(data->gpio);
    
    pr_info("roy-gpio-irq: Thread handler - GPIO value: %d\n", gpio_val);
    
    // Simulate some work
    msleep(10);
    
    return IRQ_HANDLED;
}

// Sysfs show for interrupt count
static ssize_t irq_count_show(struct device *dev, 
                              struct device_attribute *attr, char *buf)
{
    return sprintf(buf, "%lu\n", irq_data->irq_count);
}

static DEVICE_ATTR_RO(irq_count);

static int gpio_irq_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    int ret;
    unsigned long flags = IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING;
    
    pr_info("roy-gpio-irq: Probing interrupt driver\n");
    
    // Allocate data structure
    irq_data = devm_kzalloc(dev, sizeof(*irq_data), GFP_KERNEL);
    if (!irq_data)
        return -ENOMEM;
    
    irq_data->pdev = pdev;
    
    // Get GPIO from device tree
    irq_data->gpio = of_get_named_gpio(dev->of_node, "gpios", 0);
    if (!gpio_is_valid(irq_data->gpio)) {
        dev_err(dev, "Invalid GPIO\n");
        return -EINVAL;
    }
    
    pr_info("roy-gpio-irq: Using GPIO %d\n", irq_data->gpio);
    
    // Request GPIO
    ret = devm_gpio_request(dev, irq_data->gpio, DRIVER_NAME);
    if (ret) {
        dev_err(dev, "Failed to request GPIO\n");
        return ret;
    }
    
    // Configure as input
    ret = gpio_direction_input(irq_data->gpio);
    if (ret) {
        dev_err(dev, "Failed to set GPIO as input\n");
        return ret;
    }
    
    // Get IRQ number from GPIO
    irq_data->irq = gpio_to_irq(irq_data->gpio);
    if (irq_data->irq < 0) {
        dev_err(dev, "Failed to get IRQ number\n");
        return irq_data->irq;
    }
    
    pr_info("roy-gpio-irq: IRQ number: %d\n", irq_data->irq);
    
    // Request threaded IRQ
    ret = devm_request_threaded_irq(dev, irq_data->irq,
                                    gpio_irq_handler,
                                    gpio_irq_thread,
                                    flags,
                                    DRIVER_NAME,
                                    irq_data);
    if (ret) {
        dev_err(dev, "Failed to request IRQ\n");
        return ret;
    }
    
    // Create sysfs attribute
    ret = device_create_file(dev, &dev_attr_irq_count);
    if (ret) {
        dev_err(dev, "Failed to create sysfs attribute\n");
        return ret;
    }
    
    platform_set_drvdata(pdev, irq_data);
    
    pr_info("roy-gpio-irq: Driver probed successfully\n");
    pr_info("roy-gpio-irq: Interrupt count: /sys/devices/platform/roy-gpio-irq/irq_count\n");
    
    return 0;
}

static int gpio_irq_remove(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    
    device_remove_file(dev, &dev_attr_irq_count);
    
    pr_info("roy-gpio-irq: Driver removed. Total interrupts: %lu\n",
            irq_data->irq_count);
    
    return 0;
}

static const struct of_device_id gpio_irq_of_match[] = {
    { .compatible = "roy,gpio-irq-device", },
    { }
};
MODULE_DEVICE_TABLE(of, gpio_irq_of_match);

static struct platform_driver gpio_irq_driver = {
    .probe = gpio_irq_probe,
    .remove = gpio_irq_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = gpio_irq_of_match,
    },
};

module_platform_driver(gpio_irq_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("GPIO interrupt driver with threaded IRQ");
MODULE_VERSION("1.0");
```

**Device Tree Overlay** `roy-gpio-irq.dts`:
```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target = <&gpio>;
        __overlay__ {
            roy_gpio_irq_pins: roy_gpio_irq_pins {
                brcm,pins = <27>;  // GPIO27 for interrupt
                brcm,function = <0>;  // Input
                brcm,pull = <2>;  // Pull-up
            };
        };
    };
    
    fragment@1 {
        target-path = "/";
        __overlay__ {
            roy_gpio_irq: roy-gpio-irq-device {
                compatible = "roy,gpio-irq-device";
                gpios = <&gpio 27 0>;
                pinctrl-names = "default";
                pinctrl-0 = <&roy_gpio_irq_pins>;
                status = "okay";
            };
        };
    };
};
```

---

## Part 7: I2C Device Drivers

### I2C Driver Example (MPU6050 Accelerometer)

**Driver** `recipes-kernel/modules/i2c-driver/files/mpu6050_drv.c`:
```c
#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "mpu6050"
#define CLASS_NAME "roy_i2c"

// MPU6050 Registers
#define MPU6050_PWR_MGMT_1   0x6B
#define MPU6050_ACCEL_XOUT_H 0x3B
#define MPU6050_GYRO_XOUT_H  0x43
#define MPU6050_WHO_AM_I     0x75

struct mpu6050_data {
    struct i2c_client *client;
    struct cdev cdev;
    dev_t dev_num;
    struct class *class;
    struct device *device;
    int16_t accel_x, accel_y, accel_z;
    int16_t gyro_x, gyro_y, gyro_z;
};

static struct mpu6050_data *mpu_data;

// I2C read function
static int mpu6050_read_reg(struct i2c_client *client, u8 reg, u8 *val)
{
    int ret;
    
    ret = i2c_smbus_read_byte_data(client, reg);
    if (ret < 0)
        return ret;
    
    *val = ret;
    return 0;
}

// I2C write function
static int mpu6050_write_reg(struct i2c_client *client, u8 reg, u8 val)
{
    return i2c_smbus_write_byte_data(client, reg, val);
}

// Read sensor data
static int mpu6050_read_data(struct mpu6050_data *data)
{
    struct i2c_client *client = data->client;
    u8 buffer[14];
    int i, ret;
    
    // Read all sensor data (accel + temp + gyro)
    for (i = 0; i < 14; i++) {
        ret = mpu6050_read_reg(client, MPU6050_ACCEL_XOUT_H + i, &buffer[i]);
        if (ret < 0)
            return ret;
    }
    
    // Parse accelerometer data (big-endian)
    data->accel_x = (buffer[0] << 8) | buffer[1];
    data->accel_y = (buffer[2] << 8) | buffer[3];
    data->accel_z = (buffer[4] << 8) | buffer[5];
    
    // Parse gyroscope data
    data->gyro_x = (buffer[8] << 8) | buffer[9];
    data->gyro_y = (buffer[10] << 8) | buffer[11];
    data->gyro_z = (buffer[12] << 8) | buffer[13];
    
    return 0;
}

// Character device operations
static int mpu6050_dev_open(struct inode *inode, struct file *file)
{
    pr_info("mpu6050: Device opened\n");
    return 0;
}

static int mpu6050_dev_release(struct inode *inode, struct file *file)
{
    pr_info("mpu6050: Device closed\n");
    return 0;
}

static ssize_t mpu6050_dev_read(struct file *file, char __user *buf,
                                size_t count, loff_t *offset)
{
    char buffer[128];
    int len;
    int ret;
    
    if (*offset > 0)
        return 0;
    
    // Read fresh data from sensor
    ret = mpu6050_read_data(mpu_data);
    if (ret < 0)
        return ret;
    
    // Format data
    len = snprintf(buffer, sizeof(buffer),
                   "Accel: X=%6d Y=%6d Z=%6d\n"
                   "Gyro:  X=%6d Y=%6d Z=%6d\n",
                   mpu_data->accel_x, mpu_data->accel_y, mpu_data->accel_z,
                   mpu_data->gyro_x, mpu_data->gyro_y, mpu_data->gyro_z);
    
    if (copy_to_user(buf, buffer, len))
        return -EFAULT;
    
    *offset += len;
    return len;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = mpu6050_dev_open,
    .release = mpu6050_dev_release,
    .read = mpu6050_dev_read,
};

// I2C driver probe
static int mpu6050_probe(struct i2c_client *client)
{
    u8 who_am_i;
    int ret;
    
    dev_info(&client->dev, "Probing MPU6050 driver\n");
    
    // Allocate data structure
    mpu_data = devm_kzalloc(&client->dev, sizeof(*mpu_data), GFP_KERNEL);
    if (!mpu_data)
        return -ENOMEM;
    
    mpu_data->client = client;
    i2c_set_clientdata(client, mpu_data);
    
    // Check WHO_AM_I register
    ret = mpu6050_read_reg(client, MPU6050_WHO_AM_I, &who_am_i);
    if (ret < 0) {
        dev_err(&client->dev, "Failed to read WHO_AM_I\n");
        return ret;
    }
    
    dev_info(&client->dev, "WHO_AM_I: 0x%02X\n", who_am_i);
    
    if (who_am_i != 0x68) {
        dev_err(&client->dev, "Invalid WHO_AM_I value\n");
        return -ENODEV;
    }
    
    // Wake up device
    ret = mpu6050_write_reg(client, MPU6050_PWR_MGMT_1, 0x00);
    if (ret < 0) {
        dev_err(&client->dev, "Failed to wake up device\n");
        return ret;
    }
    
    msleep(100);
    
    // Create character device
    ret = alloc_chrdev_region(&mpu_data->dev_num, 0, 1, DEVICE_NAME);
    if (ret < 0)
        return ret;
    
    cdev_init(&mpu_data->cdev, &fops);
    ret = cdev_add(&mpu_data->cdev, mpu_data->dev_num, 1);
    if (ret < 0) {
        unregister_chrdev_region(mpu_data->dev_num, 1);
        return ret;
    }
    
    mpu_data->class = class_create(CLASS_NAME);
    if (IS_ERR(mpu_data->class)) {
        cdev_del(&mpu_data->cdev);
        unregister_chrdev_region(mpu_data->dev_num, 1);
        return PTR_ERR(mpu_data->class);
    }
    
    mpu_data->device = device_create(mpu_data->class, NULL,
                                     mpu_data->dev_num, NULL, DEVICE_NAME);
    if (IS_ERR(mpu_data->device)) {
        class_destroy(mpu_data->class);
        cdev_del(&mpu_data->cdev);
        unregister_chrdev_region(mpu_data->dev_num, 1);
        return PTR_ERR(mpu_data->device);
    }
    
    dev_info(&client->dev, "MPU6050 driver probed successfully\n");
    return 0;
}

static void mpu6050_remove(struct i2c_client *client)
{
    // Put device to sleep
    mpu6050_write_reg(client, MPU6050_PWR_MGMT_1, 0x40);
    
    device_destroy(mpu_data->class, mpu_data->dev_num);
    class_destroy(mpu_data->class);
    cdev_del(&mpu_data->cdev);
    unregister_chrdev_region(mpu_data->dev_num, 1);
    
    dev_info(&client->dev, "MPU6050 driver removed\n");
}

static const struct i2c_device_id mpu6050_id[] = {
    { "mpu6050", 0 },
    { }
};
MODULE_DEVICE_TABLE(i2c, mpu6050_id);

static const struct of_device_id mpu6050_of_match[] = {
    { .compatible = "invensense,mpu6050", },
    { }
};
MODULE_DEVICE_TABLE(of, mpu6050_of_match);

static struct i2c_driver mpu6050_driver = {
    .driver = {
        .name = "mpu6050",
        .of_match_table = mpu6050_of_match,
    },
    .probe = mpu6050_probe,
    .remove = mpu6050_remove,
    .id_table = mpu6050_id,
};

module_i2c_driver(mpu6050_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("MPU6050 I2C driver");
MODULE_VERSION("1.0");
```

**Device Tree Overlay** `mpu6050.dts`:
```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target = <&i2c1>;
        __overlay__ {
            #address-cells = <1>;
            #size-cells = <0>;
            status = "okay";
            
            mpu6050: mpu6050@68 {
                compatible = "invensense,mpu6050";
                reg = <0x68>;
                status = "okay";
            };
        };
    };
};
```

---

## Part 8: SPI Device Drivers

### SPI Driver Example (MCP3008 ADC)

**Driver** `recipes-kernel/modules/spi-driver/files/mcp3008_drv.c`:
```c
#include <linux/module.h>
#include <linux/spi/spi.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "mcp3008"
#define NUM_CHANNELS 8

struct mcp3008_data {
    struct spi_device *spi;
    struct cdev cdev;
    dev_t dev_num;
    struct class *class;
    struct device *device;
};

static struct mcp3008_data *adc_data;

// Read ADC channel
static int mcp3008_read_channel(struct spi_device *spi, int channel)
{
    u8 tx[3], rx[3];
    int ret;
    
    if (channel < 0 || channel >= NUM_CHANNELS)
        return -EINVAL;
    
    // Build command (single-ended mode)
    tx[0] = 0x01;  // Start bit
    tx[1] = (0x80 | (channel << 4));  // Single-ended, channel select
    tx[2] = 0x00;
    
    ret = spi_write_then_read(spi, tx, 3, rx, 3);
    if (ret < 0)
        return ret;
    
    // Extract 10-bit value
    return ((rx[1] & 0x03) << 8) | rx[2];
}

// Character device operations
static int mcp3008_open(struct inode *inode, struct file *file)
{
    pr_info("mcp3008: Device opened\n");
    return 0;
}

static int mcp3008_release(struct inode *inode, struct file *file)
{
    pr_info("mcp3008: Device closed\n");
    return 0;
}

static ssize_t mcp3008_read(struct file *file, char __user *buf,
                            size_t count, loff_t *offset)
{
    char buffer[256];
    int len = 0;
    int i, value;
    
    if (*offset > 0)
        return 0;
    
    // Read all channels
    for (i = 0; i < NUM_CHANNELS; i++) {
        value = mcp3008_read_channel(adc_data->spi, i);
        if (value < 0)
            return value;
        
        len += snprintf(buffer + len, sizeof(buffer) - len,
                       "CH%d: %4d (%.2fV)\n", i, value, value * 3.3 / 1023.0);
    }
    
    if (copy_to_user(buf, buffer, len))
        return -EFAULT;
    
    *offset += len;
    return len;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = mcp3008_open,
    .release = mcp3008_release,
    .read = mcp3008_read,
};

// SPI driver probe
static int mcp3008_probe(struct spi_device *spi)
{
    int ret;
    
    dev_info(&spi->dev, "Probing MCP3008 SPI driver\n");
    
    // Configure SPI
    spi->mode = SPI_MODE_0;
    spi->bits_per_word = 8;
    spi->max_speed_hz = 1000000;  // 1MHz
    
    ret = spi_setup(spi);
    if (ret < 0) {
        dev_err(&spi->dev, "SPI setup failed\n");
        return ret;
    }
    
    // Allocate data structure
    adc_data = devm_kzalloc(&spi->dev, sizeof(*adc_data), GFP_KERNEL);
    if (!adc_data)
        return -ENOMEM;
    
    adc_data->spi = spi;
    spi_set_drvdata(spi, adc_data);
    
    // Create character device
    ret = alloc_chrdev_region(&adc_data->dev_num, 0, 1, DEVICE_NAME);
    if (ret < 0)
        return ret;
    
    cdev_init(&adc_data->cdev, &fops);
    ret = cdev_add(&adc_data->cdev, adc_data->dev_num, 1);
    if (ret < 0) {
        unregister_chrdev_region(adc_data->dev_num, 1);
        return ret;
    }
    
    adc_data->class = class_create("mcp3008");
    if (IS_ERR(adc_data->class)) {
        cdev_del(&adc_data->cdev);
        unregister_chrdev_region(adc_data->dev_num, 1);
        return PTR_ERR(adc_data->class);
    }
    
    adc_data->device = device_create(adc_data->class, NULL,
                                     adc_data->dev_num, NULL, DEVICE_NAME);
    if (IS_ERR(adc_data->device)) {
        class_destroy(adc_data->class);
        cdev_del(&adc_data->cdev);
        unregister_chrdev_region(adc_data->dev_num, 1);
        return PTR_ERR(adc_data->device);
    }
    
    dev_info(&spi->dev, "MCP3008 driver probed successfully\n");
    return 0;
}

static void mcp3008_remove(struct spi_device *spi)
{
    device_destroy(adc_data->class, adc_data->dev_num);
    class_destroy(adc_data->class);
    cdev_del(&adc_data->cdev);
    unregister_chrdev_region(adc_data->dev_num, 1);
    
    dev_info(&spi->dev, "MCP3008 driver removed\n");
}

static const struct of_device_id mcp3008_of_match[] = {
    { .compatible = "microchip,mcp3008", },
    { }
};
MODULE_DEVICE_TABLE(of, mcp3008_of_match);

static struct spi_driver mcp3008_driver = {
    .driver = {
        .name = "mcp3008",
        .of_match_table = mcp3008_of_match,
    },
    .probe = mcp3008_probe,
    .remove = mcp3008_remove,
};

module_spi_driver(mcp3008_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("MCP3008 SPI ADC driver");
MODULE_VERSION("1.0");
```

**Device Tree Overlay** `mcp3008.dts`:
```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target = <&spi0>;
        __overlay__ {
            #address-cells = <1>;
            #size-cells = <0>;
            status = "okay";
            
            mcp3008: mcp3008@0 {
                compatible = "microchip,mcp3008";
                reg = <0>;  // CE0
                spi-max-frequency = <1000000>;
                status = "okay";
            };
        };
    };
};
```

---

## Part 9: Advanced Driver Topics

### Driver with Workqueue

**Driver** `workqueue_driver.c`:
```c
#include <linux/module.h>
#include <linux/workqueue.h>
#include <linux/slab.h>
#include <linux/gpio.h>

#define GPIO_LED 17

struct work_data {
    struct work_struct work;
    int count;
};

static struct workqueue_struct *wq;

// Work handler function
static void work_handler(struct work_struct *work)
{
    struct work_data *data = container_of(work, struct work_data, work);
    
    pr_info("roy_wq: Work handler executed (count: %d)\n", data->count);
    
    // Toggle LED
    gpio_set_value(GPIO_LED, data->count % 2);
    
    data->count++;
    
    // Re-schedule work after 1 second
    if (data->count < 10) {
        msleep(1000);
        queue_work(wq, work);
    } else {
        kfree(data);
    }
}

static int __init wq_init(void)
{
    struct work_data *data;
    
    pr_info("roy_wq: Initializing workqueue driver\n");
    
    // Request GPIO
    if (gpio_request(GPIO_LED, "wq_led") < 0) {
        pr_err("roy_wq: Failed to request GPIO\n");
        return -1;
    }
    
    gpio_direction_output(GPIO_LED, 0);
    
    // Create workqueue
    wq = create_singlethread_workqueue("roy_workqueue");
    if (!wq) {
        gpio_free(GPIO_LED);
        return -ENOMEM;
    }
    
    // Allocate work data
    data = kmalloc(sizeof(*data), GFP_KERNEL);
    if (!data) {
        destroy_workqueue(wq);
        gpio_free(GPIO_LED);
        return -ENOMEM;
    }
    
    data->count = 0;
    INIT_WORK(&data->work, work_handler);
    
    // Queue work
    queue_work(wq, &data->work);
    
    pr_info("roy_wq: Workqueue initialized\n");
    return 0;
}

static void __exit wq_exit(void)
{
    flush_workqueue(wq);
    destroy_workqueue(wq);
    gpio_set_value(GPIO_LED, 0);
    gpio_free(GPIO_LED);
    
    pr_info("roy_wq: Workqueue driver unloaded\n");
}

module_init(wq_init);
module_exit(wq_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("Workqueue driver example");
```

### Driver with Timer

**Driver** `timer_driver.c`:
```c
#include <linux/module.h>
#include <linux/timer.h>
#include <linux/jiffies.h>
#include <linux/gpio.h>

#define GPIO_LED 17
#define TIMER_INTERVAL_MS 500

static struct timer_list my_timer;
static int led_state = 0;

// Timer callback function
static void timer_callback(struct timer_list *t)
{
    // Toggle LED
    led_state = !led_state;
    gpio_set_value(GPIO_LED, led_state);
    
    pr_info("roy_timer: LED toggled to %d\n", led_state);
    
    // Re-arm timer
    mod_timer(&my_timer, jiffies + msecs_to_jiffies(TIMER_INTERVAL_MS));
}

static int __init timer_init(void)
{
    pr_info("roy_timer: Initializing timer driver\n");
    
    // Request GPIO
    if (gpio_request(GPIO_LED, "timer_led") < 0) {
        pr_err("roy_timer: Failed to request GPIO\n");
        return -1;
    }
    
    gpio_direction_output(GPIO_LED, 0);
    
    // Setup timer
    timer_setup(&my_timer, timer_callback, 0);
    
    // Start timer
    mod_timer(&my_timer, jiffies + msecs_to_jiffies(TIMER_INTERVAL_MS));
    
    pr_info("roy_timer: Timer started\n");
    return 0;
}

static void __exit timer_exit(void)
{
    del_timer(&my_timer);
    gpio_set_value(GPIO_LED, 0);
    gpio_free(GPIO_LED);
    
    pr_info("roy_timer: Timer driver unloaded\n");
}

module_init(timer_init);
module_exit(timer_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("Timer driver example");
```

### Driver with Debugfs

**Driver** `debugfs_driver.c`:
```c
#include <linux/module.h>
#include <linux/debugfs.h>
#include <linux/gpio.h>

#define GPIO_LED 17

static struct dentry *debug_dir;
static struct dentry *debug_file;
static int led_value = 0;

// Debugfs read callback
static int led_get(void *data, u64 *val)
{
    *val = gpio_get_value(GPIO_LED);
    return 0;
}

// Debugfs write callback
static int led_set(void *data, u64 val)
{
    if (val > 1)
        return -EINVAL;
    
    led_value = val;
    gpio_set_value(GPIO_LED, led_value);
    
    pr_info("roy_debugfs: LED set to %d\n", led_value);
    return 0;
}

DEFINE_SIMPLE_ATTRIBUTE(led_fops, led_get, led_set, "%llu\n");

static int __init debugfs_init(void)
{
    pr_info("roy_debugfs: Initializing debugfs driver\n");
    
    // Request GPIO
    if (gpio_request(GPIO_LED, "debugfs_led") < 0) {
        pr_err("roy_debugfs: Failed to request GPIO\n");
        return -1;
    }
    
    gpio_direction_output(GPIO_LED, 0);
    
    // Create debugfs directory
    debug_dir = debugfs_create_dir("roy_driver", NULL);
    if (!debug_dir) {
        gpio_free(GPIO_LED);
        return -ENOMEM;
    }
    
    // Create debugfs file
    debug_file = debugfs_create_file("led_control", 0644, debug_dir,
                                     NULL, &led_fops);
    if (!debug_file) {
        debugfs_remove_recursive(debug_dir);
        gpio_free(GPIO_LED);
        return -ENOMEM;
    }
    
    pr_info("roy_debugfs: Created /sys/kernel/debug/roy_driver/led_control\n");
    return 0;
}

static void __exit debugfs_exit(void)
{
    debugfs_remove_recursive(debug_dir);
    gpio_set_value(GPIO_LED, 0);
    gpio_free(GPIO_LED);
    
    pr_info("roy_debugfs: Debugfs driver unloaded\n");
}

module_init(debugfs_init);
module_exit(debugfs_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Roy");
MODULE_DESCRIPTION("Debugfs driver example");
```

---

## Part 10: Debugging and Testing

### Kernel Debugging Tools

**1. printk and pr_* macros:**
```c
pr_emerg("Emergency message\n");
pr_alert("Alert message\n");
pr_crit("Critical message\n");
pr_err("Error message\n");
pr_warn("Warning message\n");
pr_notice("Notice message\n");
pr_info("Info message\n");
pr_debug("Debug message\n");  // Only if DEBUG defined

// With device
dev_err(&dev->dev, "Device error\n");
dev_warn(&dev->dev, "Device warning\n");
dev_info(&dev->dev, "Device info\n");
```

**2. Dynamic debugging:**
```bash
# Enable all pr_debug() in a module
echo "module roy_driver +p" > /sys/kernel/debug/dynamic_debug/control

# Enable by function
echo "func gpio_probe +p" > /sys/kernel/debug/dynamic_debug/control

# Enable by file
echo "file gpio_drv.c +p" > /sys/kernel/debug/dynamic_debug/control
```

**3. View kernel logs:**
```bash
# Real-time kernel log
dmesg -w

# Filter by level
dmesg -l err,warn

# Follow specific module
dmesg | grep roy_driver

# Use journalctl (systemd)
journalctl -k -f
```

### Testing Drivers

**Test script** `recipes-support/driver-test/files/test_drivers.sh`:
```bash
#!/bin/bash

echo "=== Driver Testing Script ==="

# Test character device
echo "Testing character device..."
if [ -c /dev/roychar ]; then
    echo "Hello from test" > /dev/roychar
    cat /dev/roychar
    echo "✓ Character device working"
else
    echo "✗ Character device not found"
fi

# Test GPIO driver
echo -e "\nTesting GPIO driver..."
if [ -d /sys/kernel/roy_gpio ]; then
    echo 1 > /sys/kernel/roy_gpio/state
    sleep 1
    echo 0 > /sys/kernel/roy_gpio/state
    echo "✓ GPIO driver working"
else
    echo "✗ GPIO driver not found"
fi

# Test interrupt driver
echo -e "\nTesting interrupt driver..."
if [ -f /sys/devices/platform/roy-gpio-irq/irq_count ]; then
    cat /sys/devices/platform/roy-gpio-irq/irq_count
    echo "✓ Interrupt driver working"
else
    echo "✗ Interrupt driver not found"
fi

# Test I2C driver (MPU6050)
echo -e "\nTesting I2C driver..."
if [ -c /dev/mpu6050 ]; then
    cat /dev/mpu6050
    echo "✓ I2C driver working"
else
    echo "✗ I2C driver not found"
fi

# Test SPI driver (MCP3008)
echo -e "\nTesting SPI driver..."
if [ -c /dev/mcp3008 ]; then
    cat /dev/mcp3008
    echo "✓ SPI driver working"
else
    echo "✗ SPI driver not found"
fi

# Module information
echo -e "\n=== Loaded Modules ==="
lsmod | grep -E "(roy|mpu|mcp)"

echo -e "\n=== Testing Complete ==="
```

### GDB Kernel Debugging

**1. Build kernel with debug symbols:**
Add to `conf/local.conf`:
```bitbake
KERNEL_EXTRA_ARGS += "CONFIG_DEBUG_INFO=y"
KERNEL_EXTRA_ARGS += "CONFIG_GDB_SCRIPTS=y"
```

**2. Setup KGDB over serial:**
```bash
# On target (RPi4), add to kernel cmdline:
kgdboc=ttyAMA0,115200 kgdbwait

# On host, connect via serial:
gdb vmlinux
(gdb) target remote /dev/ttyUSB0
```

### Memory Debugging

**1. KASAN (Kernel Address Sanitizer):**
```bitbake
KERNEL_EXTRA_ARGS += "CONFIG_KASAN=y"
```

**2. Check for memory leaks:**
```bash
cat /sys/kernel/debug/kmemleak
echo scan > /sys/kernel/debug/kmemleak
```

### Performance Profiling

**1. ftrace:**
```bash
# Enable function tracing
echo function > /sys/kernel/debug/tracing/current_tracer
echo roy_* > /sys/kernel/debug/tracing/set_ftrace_filter
echo 1 > /sys/kernel/debug/tracing/tracing_on

# View trace
cat /sys/kernel/debug/tracing/trace
```

**2. perf:**
```bash
# Profile driver
perf record -g insmod roy_driver.ko
perf report
```

---

## Building Complete System

### Custom Image Recipe

**Create** `meta-drivers/recipes-core/images/driver-dev-image.bb`:
```bitbake
SUMMARY = "Roy's driver development image"
DESCRIPTION = "Complete image with all driver examples"

LICENSE = "MIT"

inherit core-image

# Base features
IMAGE_FEATURES += "ssh-server-dropbear"
IMAGE_FEATURES += "tools-debug"
IMAGE_FEATURES += "tools-sdk"
IMAGE_FEATURES += "dev-pkgs"

# Core packages
IMAGE_INSTALL:append = " \
    kernel-modules \
    kernel-devsrc \
    i2c-tools \
    spitools \
    python3 \
    bash \
    vim \
    htop \
    strace \
    gdb \
"

# All driver modules
IMAGE_INSTALL:append = " \
    simple-module \
    chardev-driver \
    platform-driver \
    gpio-driver \
    interrupt-driver \
    i2c-driver \
    spi-driver \
"

# Test utilities
IMAGE_INSTALL:append = " \
    driver-test \
"

IMAGE_ROOTFS_EXTRA_SPACE = "1000000"
```

### Build Complete System

```bash
cd ~/yocto-drivers/poky/build-rpi4

# Build everything
bitbake driver-dev-image

# Flash to SD card
sudo dd if=tmp/deploy/images/raspberrypi4-64/driver-dev-image-raspberrypi4-64.rootfs.wic \
    of=/dev/sdX bs=4M status=progress && sync
```

---

## Quick Reference

### Common Commands

```bash
# Load module
insmod module_name.ko

# Remove module
rmmod module_name

# List loaded modules
lsmod

# Module information
modinfo module_name.ko

# View devices
ls -l /dev/

# Kernel messages
dmesg | tail -20

# I2C detection
i2cdetect -y 1

# SPI test
spidev_test -D /dev/spidev0.0

# GPIO export
echo 17 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio17/direction
echo 1 > /sys/class/gpio/gpio17/value
```

### Recipe Template

```bitbake
SUMMARY = "Driver summary"
DESCRIPTION = "Driver description"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = "file://driver.c \
           file://Makefile \
          "

S = "${WORKDIR}"

KERNEL_MODULE_AUTOLOAD += "driver"
```

---

## Troubleshooting

### Common Issues

**1. Module won't load:**
```bash
# Check kernel logs
dmesg | grep -i error

# Check dependencies
modinfo module_name.ko

# Force load
insmod module_name.ko
```

**2. Device not created:**
```bash
# Check udev rules
udevadm info /dev/device_name

# Reload udev
udevadm control --reload
```

**3. Build errors:**
```bash
# Clean and rebuild
bitbake -c clean driver-name
bitbake driver-name

# Check logs
cat tmp/work/.../temp/log.do_compile
```

---

## Resources

- Linux Device Drivers (LDD3): https://lwn.net/Kernel/LDD3/
- Kernel Documentation: https://www.kernel.org/doc/html/latest/
- Raspberry Pi Documentation: https://www.raspberrypi.com/documentation/
- Yocto Project: https://docs.yoctoproject.org/
- Linux Driver Development Course: https://bootlin.com/training/kernel/

---

**Created for Roy's Linux device driver development on Raspberry Pi 4 with Yocto**
