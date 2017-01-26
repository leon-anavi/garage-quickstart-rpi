#!/bin/bash

ask() {
    # http://djm.me/ask
    local prompt default REPLY

    while true; do

        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi

        # Ask the question (not using "read -p" as it uses stderr not stdout)
        echo -n "$1 [$prompt] "

        # Read the answer (use /dev/tty in case stdin is redirected from somewhere else)
        read REPLY </dev/tty

        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi

        # Check if the reply is valid
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac

    done
}

if [[ $EUID -ne 0 ]]; then
  echo ""
  echo "  This script must be run as root" 1>&2
  echo ""
  exit 1
fi

if [ -z "$3" ]; then
  echo ""
  echo "   Flash a built image with an ATS Garage device config file baked in."
  echo ""
  echo "   Usage: ./flash-configured-image.sh imagefile configfile device"
  echo ""
  echo "    imagefile  : An image file generated by bitbake."
  echo "      Example: ./build/tmp/deploy/images/raspberrypi3/core-image-minimal-raspberrypi3.rpi-sdimg-ota"
  echo ""
  echo "    configfile : A config file downloaded from ATS Garage."
  echo "      Example: sota_client_5206671b-cc2a-42e8-9227-736588bf6cf0.toml"
  echo ""
  echo "    device     : The device to flash, with no trailing slash."
  echo "      Example: /dev/sdb"
  echo ""
  echo "   The following utilities are prerequisites:"
  echo ""
  echo "    dd"
  echo "    parted"
  echo "    e2fsck"
  echo "    fdisk"
  echo "    resize2fs"
  echo ""
  exit 1
fi

command -v dd >/dev/null 2>&1 || { echo >&2 "This script requires dd, but it's not installed.  Aborting."; exit 1; }
command -v parted >/dev/null 2>&1 || { echo >&2 "This script requires parted, but it's not installed.  Aborting."; exit 1; }
command -v e2fsck >/dev/null 2>&1 || { echo >&2 "This script requires e2fsck, but it's not installed.  Aborting."; exit 1; }
command -v fdisk >/dev/null 2>&1 || { echo >&2 "This script requires fdisk, but it's not installed.  Aborting."; exit 1; }
command -v resize2fs >/dev/null 2>&1 || { echo >&2 "This script requires resize2fs, but it's not installed.  Aborting."; exit 1; }


set -euo pipefail

IMAGE_TO_FLASH=$1
SOTA_CONFIG_FILE=$2
DEVICE_TO_FLASH=$3

echo " "
echo "   Writing image file: $IMAGE_TO_FLASH "
echo "   to device         : $DEVICE_TO_FLASH "
echo "   using config file : $SOTA_CONFIG_FILE"
echo " "
if ask "Do you want to continue?" N; then
    echo " "
else
    exit 1
fi

echo "Cleaning up any leftover files from previous runs..."
umount mnt-temp || true
rm image-to-flash-temp.img || true
rmdir mnt-temp || true

echo "Unmounting all partitions on $DEVICE_TO_FLASH"
umount $DEVICE_TO_FLASH* || true
sleep 2
mkdir mnt-temp

echo "Creating temporary image file from $IMAGE_TO_FLASH..."
cp $IMAGE_TO_FLASH image-to-flash-temp.img

echo "Mounting temporary image file..."
mount -o rw,loop,offset=$(expr 512 \* $(fdisk -l image-to-flash-temp.img | tail -n 1 | awk '{print $2}')) image-to-flash-temp.img ./mnt-temp
sleep 2

echo "Adding config file to image..."
cp $SOTA_CONFIG_FILE mnt-temp/boot/sota.toml
sleep 1

echo "Unmounting image..."
umount -f ./mnt-temp
sleep 2

echo "Writing image to $DEVICE_TO_FLASH..."
dd if=image-to-flash-temp.img of=$DEVICE_TO_FLASH bs=32M && sync
sleep 2

# It turns out there are card readers that give their partitions funny names, like
# "/dev/mmcblk0" will be the device, but the partitions are called "/dev/mmcblk0p1"
# for example. Better to just get the name of the partition after we flash it.
SECOND_PARTITION=$(fdisk -l $DEVICE_TO_FLASH | tail -n 1 | awk '{print $1}')

echo "Resizing rootfs partition to fill all of $DEVICE_TO_FLASH..."
parted -s $DEVICE_TO_FLASH resizepart 2 '100%'
sleep 2
e2fsck -f $SECOND_PARTITION || true
sleep 2

echo "Resizing filesystem on $SECOND_PARTITION to match partition size..."
resize2fs -p $SECOND_PARTITION
sleep 2

echo "Cleaning up..."
rm image-to-flash-temp.img || true
rmdir mnt-temp || true

echo "Done!"

