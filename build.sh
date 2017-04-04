### GCC 4.9.x
### I'm using UBERTC https://bitbucket.org/UBERTC/aarch64-linux-android-4.9-kernel
# test script ※編集中

clear

export ARCH=arm64
### See prefix of file names in the toolchain's bin directory

export CROSS_COMPILE=$PWD/../../../prebuilts/gcc/darwin-x86/aarch64/aarch64-linux-android-4.9-kernel/bin/aarch64-linux-android-

export KBUILD_DIFFCONFIG=kagura_diffconfig

THREAD="-j$(grep -c ^processor /proc/cpuinfo)"
BIN_DIR=out/$TARGET_DEVICE/bin
OBJ_DIR=out/$TARGET_DEVICE/obj
mkdir -p $BIN_DIR
mkdir -p $OBJ_DIR

make -C $PWD O=$OBJ_DIR msm-perf_defconfig || exit -1
nice -n 10 make O=$OBJ_DIR $THREAD 2>&1 | tee make.log

echo "checking for compiled kernel..."
if [ -f arch/arm64/boot/Image.gz-dtb ]
then

	echo "DONE"

	### F8332
	/final_files/mkbootimg \
	--kernel $OBJ_DIR/arch/arm64/boot/Image.gz-dtb \
	--ramdisk ../final_files/ramdisk_kagura_dsds.cpio.gz \
	--cmdline "androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x237 ehci-hcd.park=3 lpm_levels.sleep_disabled=1 cma=16M@0-0xffffffff coherent_pool=2M enforcing=0" \
	--base 0x80000000 \
	--pagesize 4096 \
	--ramdisk_offset 0x02200000 \
	--tags_offset 0x02000000 \
	--output ../final_files/boot_F8332.img

	### Version number
	echo -n "Enter version number: "
	read version

	if [ -e ../final_files/boot_F8332.img ]
	then

		### Zip boot.img
		cd ../final_files/
		mv boot_F8332.img boot.img
		zip XZ_AndroPlusKernel_Permissive_v.zip boot.img
		rm -f boot.img

	fi

fi
