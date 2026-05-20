#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# run_qemu.sh — Build and run smart shoe QEMU test
# Usage:
#   ./run_qemu.sh esp32      — build for ESP32 + run in QEMU
#   ./run_qemu.sh esp32s3    — build for ESP32-S3 + run in QEMU
#   ./run_qemu.sh zephyr     — build with Zephyr + run in QEMU
#   ./run_qemu.sh gdb        — launch QEMU with GDB server on :1234
# ─────────────────────────────────────────────────────────────────────────────
set -e

TARGET=${1:-esp32}
FLASH_SIZE_BYTES=$((2 * 1024 * 1024))

case "$TARGET" in

  esp32|esp32s3)
    echo "── Building for $TARGET with ESP-IDF ──"
    . ~/esp/esp-idf/export.sh > /dev/null

    idf.py set-target "$TARGET"
    idf.py build

    echo "── Merging flash image ──"
    esptool.py --chip "$TARGET" merge_bin \
      -o build/merged.bin \
      --flash_mode dio \
      --flash_size 2MB \
      --flash_freq 40m \
      0x1000  build/bootloader/bootloader.bin \
      0x8000  build/partition_table/partition-table.bin \
      0x10000 build/smart_shoe_qemu_test.bin

    echo "── Padding to 2MB ──"
    python3 -c "
data = open('build/merged.bin','rb').read()
pad  = b'\xff' * ($FLASH_SIZE_BYTES - len(data))
open('build/flash.bin','wb').write(data + pad)
print(f'Flash image: {len(data)+len(pad)} bytes')
"

    MACHINE="esp32"
    [ "$TARGET" = "esp32s3" ] && MACHINE="esp32s3"

    echo "── Launching QEMU ($MACHINE) ──"
    qemu-system-xtensa \
      -nographic \
      -machine "$MACHINE" \
      -drive file=build/flash.bin,if=mtd,format=raw \
      -serial mon:stdio
    ;;

  gdb)
    echo "── Launching QEMU with GDB server on :1234 ──"
    . ~/esp/esp-idf/export.sh > /dev/null
    qemu-system-xtensa \
      -nographic \
      -machine esp32 \
      -drive file=build/flash.bin,if=mtd,format=raw \
      -serial mon:stdio \
      -s -S &
    sleep 1
    echo "── Connecting GDB ──"
    xtensa-esp32-elf-gdb build/smart_shoe_qemu_test.elf \
      -ex "target remote :1234" \
      -ex "break app_main" \
      -ex "continue"
    ;;

  zephyr)
    echo "── Building for Zephyr qemu_cortex_m3 ──"
    source ~/zephyrproject/.venv/bin/activate
    . ~/zephyrproject/zephyr/zephyr-env.sh
    west build -b qemu_cortex_m3 . -- -DCONF_FILE=prj.conf
    west build -t run
    ;;

  *)
    echo "Unknown target: $TARGET"
    echo "Usage: $0 [esp32|esp32s3|zephyr|gdb]"
    exit 1
    ;;
esac
