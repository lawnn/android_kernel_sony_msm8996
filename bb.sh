#!/bin/bash

# Bash Color
green='\033[01;32m'
red='\033[01;31m'
blink_red='\033[05;31m'
restore='\033[0m'

KERNEL_DIR=$PWD
IMAGE_NAME=boot

# set kernel version
if [ "$BUILD_TARGET" = 'dora' ]; then
TARGET_DEVICE=dora
else
TARGET_DEVICE=kagura
fi
BUILD_VERSION=V0.1.0

# set build user and host
export KBUILD_BUILD_VERSION="1"
export KBUILD_BUILD_USER="kernel"
export KBUILD_BUILD_HOST="lawn"

# set kernel option
KERNEL_CMDLINE="androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x237 ehci-hcd.park=3 lpm_levels.sleep_disabled=1 cma=16M@0-0xffffffff coherent_pool=2M androidboot.selinux=permissive"
KERNEL_BASEADDRESS=0x80000000
KERNEL_RAMDISK_OFFSET=0x02200000
KERNEL_TAGS_OFFSET=0x02000000
KERNEL_PAGESIZE=4096
KERNEL_DEFCONFIG=kagura_defconfig

# ramdisk
if [ "$BUILD_TARGET" = 'dora' ]; then
RAMDISK_SRC_DIR=../f8132_boot_ramdisk
RAMDISK_TMP_DIR=/tmp/f8132_boot_ramdisk
else
RAMDISK_SRC_DIR=../f8332_boot_ramdisk
RAMDISK_TMP_DIR=/tmp/f8332_boot_ramdisk
fi

IMAGE_NAME=boot
THREAD="-j$(grep -c ^processor /proc/cpuinfo)"
BIN_DIR=out/$TARGET_DEVICE/bin
OBJ_DIR=out/$TARGET_DEVICE/obj
mkdir -p $BIN_DIR
mkdir -p ${OBJ_DIR}


copy_ramdisk()
{
    echo copy $RAMDISK_SRC_DIR to $(dirname $RAMDISK_TMP_DIR)

    if [ -d $RAMDISK_TMP_DIR ]; then
        rm -rf $RAMDISK_TMP_DIR
    fi
    cp -a $RAMDISK_SRC_DIR $(dirname $RAMDISK_TMP_DIR)
    rm -rf $RAMDISK_TMP_DIR/.git
    find $RAMDISK_TMP_DIR -name .gitkeep | xargs rm --force
    find $RAMDISK_TMP_DIR -name .gitignore | xargs rm --force
}

clean_up()
{
   # force regeneration of .dtb and Image files for every compile
    rm -f $OBJ_DIR/arch/arm64/boot/Image
    rm -f $OBJ_DIR/arch/arm64/boot/Image.gz
    rm -f $OBJ_DIR/arch/arm64/boot/Image.gz-dtb
    rm -f $BIN_DIR/*.zip
    rm -f $BIN_DIR/*.img
}

make_kernel()
{

if [ "$BUILD_SELECT" = 'all' -o "$BUILD_SELECT" = 'a' ]; then
  echo -e "${red}"
  echo ""
  echo "=====> CLEANING..."
  make clean
  echo "=====> GENERATE DEFCONFIG..."
  echo -e "${restore}"
  cp -f ./arch/arm64/configs/$KERNEL_DEFCONFIG $OBJ_DIR/.config
  make -C $PWD O=$OBJ_DIR oldconfig || exit -1
fi

if [ "$BUILD_SELECT" != 'image' -a "$BUILD_SELECT" != 'i' ]; then
  echo -e "${green}"
  echo ""
  echo "=====> BUILDING..."
  echo -e "${restore}"
  if [ -e make.log ]; then
    mv make.log make_old.log
  fi
  nice -n 10 make O=${OBJ_DIR} $THREAD 2>&1 | tee make.log || exit -1
fi
}

check_compile_error()
{
   COMPILE_ERROR=`grep 'error:' ./make.log`
   if [ "$COMPILE_ERROR" ]; then
      echo -e "${red}"
      echo ""
      echo "=====> ERROR"
      echo -e "${restore}"
      grep 'error:' ./make.log
      exit -1
    fi
}

make_boot_image()
{
    ./release-tools/mkbootfs ${RAMDISK_TMP_DIR} > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio
    ./release-tools/minigzip < ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img
#   lzma < ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img
    ./release-tools/mkbootimg \
    --cmdline "${KERNEL_CMDLINE}" \
    --base ${KERNEL_BASEADDRESS} \
    --pagesize ${KERNEL_PAGESIZE} \
    --ramdisk_offset ${KERNEL_RAMDISK_OFFSET} \
    --tags_offset ${KERNEL_TAGS_OFFSET} \
    --kernel ${OBJ_DIR}/arch/arm64/boot/Image.gz-dtb \
    --ramdisk ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img \
    --output ${BIN_DIR}/${IMAGE_NAME}.img
    rm $BIN_DIR/ramdisk-$IMAGE_NAME.img
    rm $BIN_DIR/ramdisk-$IMAGE_NAME.cpio
    rm -r ${RAMDISK_TMP_DIR}
}

make_zip()
{
    if [ -d tmp ]; then
        rm -rf tmp
    fi
    mkdir -p ./tmp/META-INF/com/google/android
    cp $IMAGE_NAME.img ./tmp/
    cp $KERNEL_DIR/release-tools/update-binary ./tmp/META-INF/com/google/android/
    sed -e "s/@VERSION/$BUILD_LOCALVERSION/g" $KERNEL_DIR/release-tools/$TARGET_DEVICE/updater-script-$IMAGE_NAME.sed > ./tmp/META-INF/com/google/android/updater-script
    cd tmp && zip -rq ../cwm.zip ./* && cd ../
    SIGNAPK_DIR=$KERNEL_DIR/release-tools/signapk
    java -jar $SIGNAPK_DIR/signapk.jar -w $SIGNAPK_DIR/testkey.x509.pem $SIGNAPK_DIR/testkey.pk8 cwm.zip $BUILD_LOCALVERSION-$IMAGE_NAME-signed.zip
    rm cwm.zip
    rm -rf tmp
}

# kernel vesion
KERNEL_VERSION=`grep '^VERSION = ' ./Makefile | cut -d' ' -f3`
KERNEL_PATCHLEVEL=`grep '^PATCHLEVEL = ' ./Makefile | cut -d' ' -f3`
KERNEL_SUBLEVEL=`grep '^SUBLEVEL = ' ./Makefile | cut -d' ' -f3`
export BUILD_KERNELVERSION="$KERNEL_VERSION.$KERNEL_PATCHLEVEL.$KERNEL_SUBLEVEL"

# jenkins build number
if [ -n "$BUILD_NUMBER" ]; then
export KBUILD_BUILD_VERSION="$BUILD_NUMBER"
fi

BUILD_CROSS_COMPILE=aarch64-linux-android-4.9

# set build env
export ARCH=arm64
export CROSS_COMPILE=$PWD/../../../prebuilts/gcc/darwin-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-
. version
export LOCALVERSION="-$BUILD_LOCALVERSION"

echo ""
echo "====================================================================="
echo "    BUILD START (KERNEL VERSION $BUILD_KERNELVERSION-$BUILD_LOCALVERSION)"
echo "    toolchain: ${BUILD_CROSS_COMPILE}"
echo "====================================================================="

if [ ! -n "$1" ]; then
  echo ""
  read -p "select build? [(a)ll/(u)pdate/(i)mage default:update] " BUILD_SELECT
else
  BUILD_SELECT=$1
fi

# copy RAMDISK
echo -e "${green}"
echo ""
echo "=====> COPY RAMDISK"
echo -e "${restore}"
copy_ramdisk

# clean up
clean_up

# make start
make_kernel

echo -e "${green}"
echo ""
echo "=====> CREATE RELEASE IMAGE"
echo -e "${restore}"

# check compile error
check_compile_error

# clean release dir
if [ `find $BIN_DIR -type f | wc -l` -gt 0 ]; then
  rm -rf $BIN_DIR/*
fi
mkdir -p $BIN_DIR

# create boot image

echo -e "${green}"
echo ""
echo "=== make_boot_image ==="
echo -e "${restore}"

make_boot_image

echo "  $BIN_DIR/$IMAGE_NAME.img"
cd $BIN_DIR

# create install package
echo -e "${green}"
echo ""
echo "=== make_zip ==="
echo -e "${restore}"

make_zip

echo "  $BIN_DIR/$BUILD_LOCALVERSION-$IMAGE_NAME-signed.zip"
cd $KERNEL_DIR

echo ""
echo -e "${green}"
echo "====================================================================="
echo "    BUILD COMPLETED"
echo "====================================================================="
echo -e "${restore}"
echo ""
exit 0
