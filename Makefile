CROSS_COMPILE=riscv64-linux-gnu-
ARCH=riscv
SKIP_INSTALL_PACKAGE=no
HOME=$$(pwd)
OUT_DIR=$(HOME)/output
DEVICE=/dev/loop100
DISTURB=deepin
DEEPIN_REPO=https://mirror.iscas.ac.cn/deepin-riscv/deepin-stage1/
base_path=d1
root_img=deepin-beige-stage1-minbase


COMMIT_BOOT0='882671fcf53137aaafc3a94fa32e682cb7b921f1'
COMMIT_UBOOT='afc07cec423f17ebb4448a19435292ddacf19c9b'
COMMIT_KERNEL='fe178cf0153d98b71cb01a46c8cc050826a17e77' # equals riscv/d1-wip head
KERNEL_TAG='riscv/d1-wip'
KERNEL_RELEASE='5.19.0-AllWinnerD1-Smaeul' # must match commit!

SOURCE_BOOT0='https://github.com/smaeul/sun20i_d1_spl'
SOURCE_OPENSBI='https://github.com/smaeul/opensbi'
SOURCE_UBOOT='https://github.com/smaeul/u-boot'
SOURCE_KERNEL='https://github.com/smaeul/linux'


all: test_machine_info install_qemu install_build download_root_tarball create_rootfsimg unpack_root_tarball  \
    mount_and_setup update_root_tarball kernel boot0 uboot flash install_boot clean_rootfs

test_machine_info:
	uname -a
	echo $$(nproc)
	lscpu
	whoami
	env
	mkdir -p $(OUT_DIR)

install_qemu:
	apt update
	apt install -y qemu binfmt-support qemu-user-static curl wget
	update-binfmts --display

install_build:
	apt update
	apt install -y gdisk dosfstools g++-12-riscv64-linux-gnu build-essential \
                        libncurses-dev gawk flex bison openssl libssl-dev \
                        dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf mkbootimg \
                        fakeroot genext2fs genisoimage libconfuse-dev mtd-utils mtools qemu-utils qemu-utils squashfs-tools \
                        device-tree-compiler rauc simg2img u-boot-tools f2fs-tools arm-trusted-firmware-tools swig
	update-alternatives --install /usr/bin/riscv64-linux-gnu-gcc riscv64-gcc /usr/bin/riscv64-linux-gnu-gcc-12 10
	update-alternatives --install /usr/bin/riscv64-linux-gnu-g++ riscv64-g++ /usr/bin/riscv64-linux-gnu-g++-12 10
 
download_root_tarball:
	wget https://mirror.iscas.ac.cn/deepin-riscv/deepin-stage1/deepin-beige-stage1-minbase.tar

create_rootfsimg:
	mkdir rootfs
	fallocate -l 7G rootfs.img

	losetup -P "$(DEVICE)" rootfs.img
	parted -s -a optimal -- "$(DEVICE)" mklabel gpt
	parted -s -a optimal -- "$(DEVICE)" mkpart primary ext2 40MiB 500MiB
	parted -s -a optimal -- "$(DEVICE)" mkpart primary ext4 540MiB 100%
	partprobe "$(DEVICE)"
	mkfs.ext2 -F -L boot "$(DEVICE)p1"
	mkfs.ext4 -F -L root "$(DEVICE)p2"
	mount "$(DEVICE)p2" rootfs
	mkdir rootfs/boot
	mount "$(DEVICE)p1" rootfs/boot


unpack_root_tarball:
	pushd rootfs
		tar xpvf ../deepin-beige-stage1-minbase.tar --xattrs-include='*.*' --numeric-owner
	popd

mount_and_setup:
	pushd rootfs
		mount -t proc proc proc
		mount -B /dev dev/
		mount --make-rslave dev
		mount -B /sys sys/
		mount --make-rslave sys
		mount --bind /run run
		mount --make-rslave run

		test -L dev/shm && rm dev/shm && mkdir dev/shm
		mount --types tmpfs --options nosuid,nodev,noexec shm dev/shm
		chmod 1777 dev/shm
		
		cp --dereference /etc/resolv.conf etc/
		cat ../$(base_path)/fstab | sudo tee -a etc/fstab
	popd

update_root_tarball:
	ifeq ($(SKIP_INSTALL_PACKAGE), yes)
		exit 0
	endif
	pushd rootfs
		echo "deb [trusted=yes] $(DEEPIN_REPO) beige main" > etc/apt/sources.list
		chroot . /bin/bash -c "source /etc/profile && apt update && apt install -y systemd initramfs-tools systemd-sysv nano sudo network-manager iproute2"
		chroot . /bin/bash -c "source /etc/profile && systemctl enable systemd-networkd"
		chroot . /bin/bash -c "source /etc/profile && echo root:Riscv2022# | chpasswd"
		chroot . /bin/bash -c "source /etc/profile && echo deepin-riscv > /etc/hostname"
		ls -al boot/
	popd

kernel:
	git clone --depth=1 -b $(KERNEL_TAG) $(SOURCE_KERNEL) kernel
	pushd kernel
		export DIR=$$(PWD)
		echo "CONFIG_LOCALVERSION=$(KERNEL_RELEASE)" >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_WIRELESS=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_CFG80211=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		# enable /proc/config.gz
		echo 'CONFIG_IKCONFIG=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_IKCONFIG_PROC=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		# There is no LAN. so let there be USB-LAN
		echo 'CONFIG_USB_NET_DRIVERS=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_CATC=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_KAWETH=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_PEGASUS=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_RTL8150=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_RTL8152=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_LAN78XX=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_USBNET=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_AX8817X=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_AX88179_178A=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CDCETHER=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CDC_EEM=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CDC_NCM=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_HUAWEI_CDC_NCM=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CDC_MBIM=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_DM9601=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_SR9700=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_SR9800=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_SMSC75XX=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_SMSC95XX=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_GL620A=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_NET1080=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_PLUSB=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_MCS7830=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_RNDIS_HOST=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CDC_SUBSET_ENABLE=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CDC_SUBSET=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_ALI_M5632=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_AN2720=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_BELKIN=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_ARMLINUX=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_EPSON2888=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_KC2190=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_ZAURUS=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CX82310_ETH=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_KALMIA=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_QMI_WWAN=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_INT51X1=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_IPHETH=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_SIERRA_NET=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_VL600=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_CH9200=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_NET_AQC111=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_USB_RTL8153_ECM=m' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		# enable systemV IPC (needed by fakeroot during makepkg)
		echo 'CONFIG_SYSVIPC=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_SYSVIPC_SYSCTL=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		# enable swap
		echo 'CONFIG_SWAP=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_ZSWAP=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		# enable Cedrus VPU Drivers
		echo 'CONFIG_MEDIA_SUPPORT=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_MEDIA_CONTROLLER=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_MEDIA_CONTROLLER_REQUEST_API=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_V4L_MEM2MEM_DRIVERS=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig
		echo 'CONFIG_VIDEO_SUNXI_CEDRUS=y' >> $${DIR}/arch/riscv/configs/nezha_defconfig

		make CROSS_COMPILE=riscv64-linux-gnu- ARCH=riscv nezha_defconfig
		make CROSS_COMPILE=riscv64-linux-gnu- ARCH=riscv -j$$(nproc)
		ifeq ($$(cat .config | grep CONFIG_MODULES=y),"CONFIG_MODULES=y")
			make CROSS_COMPILE=riscv64-linux-gnu- ARCH=riscv INSTALL_MOD_PATH=../rootfs/ modules_install -j$$(nproc)
		endif
		# make CROSS_COMPILE=riscv64-linux-gnu- ARCH=riscv INSTALL_PATH=../rootfs/boot zinstall -j$$(nproc)
		# Install Kernel
		cp -v arch/riscv/boot/Image ../rootfs/boot/
		cp -v arch/riscv/boot/Image.gz ../rootfs/boot/
		# Install DTB
		# cp -v arch/riscv/boot/dts/sun20i-d1-mangopi-mq-pro-linux.dtb ../rootfs/boot/
		# cp -v .config ../rootfs/boot/latest-config
		cp -v .config ../rootfs/boot/latest-config
		ls -al ../rootfs/boot/

		git clone https://github.com/lwfinger/rtl8723ds.git
		pushd rtl8723ds
			git checkout "83032266f6fbd7a6775ecf23fb4f807343ffc6f2" # lock-version
			make CROSS_COMPILE=$(CROSS_COMPILE) ARCH=$(ARCH) KSRC=../ -j$(nproc) modules || true
		popd
		for kernel_version in $(ls ../rootfs/lib/modules/);do \
            install -D -p -m 644 "rtl8723ds/8723ds.ko" \
            "../rootfs/lib/modules/$(kernel_version)/kernel/drivers/net/wireless/8723ds.ko";\
            depmod -a -b "../rootfs" "$(kernel_version)";\
            echo '8723ds' >> 8723ds.conf;\
            mv 8723ds.conf "../rootfs/etc/modules-load.d/";\
		done
	popd


boot0:
	export DIR='sun20i_d1_spl'
	git clone https://github.com/smaeul/sun20i_d1_spl $${DIR}
	pushd $${DIR}
		git checkout "$(COMMIT_BOOT0)"
		sed -i '/Werror/d' mk/config.mk
		make CROSS_COMPILE="$(CROSS_COMPILE)" p=sun20iw1p1 mmc
	popd
	cp $${DIR}/nboot/boot0_sdcard_sun20iw1p1.bin "$(OUT_DIR)"

uboot:
	export DIR='opensbi'
	git clone -b d1-wip "$(SOURCE_OPENSBI)" $${DIR}
	pushd $${DIR}
		make CROSS_COMPILE="$(CROSS_COMPILE)" PLATFORM=generic FW_PIC=y FW_OPTIONS=0x2
	popd
	# cp opensbi/build/platform/generic/firmware/fw_dynamic.bin $(OUT_DIR)

	export DIR='u-boot'
	git clone "$(SOURCE_UBOOT)"
	wget https://raw.githubusercontent.com/sehraf/riscv-arch-image-builder/ad08db949832cf70767c32f5a3035ea88bc6eea8/uboot-makefile.patch
	pushd $${DIR}
		git checkout d1-wip
		git apply ../uboot-makefile.patch
		make CROSS_COMPILE="$(CROSS_COMPILE)" ARCH="$(ARCH)" nezha_defconfig
		make CROSS_COMPILE="$(CROSS_COMPILE)" ARCH="$(ARCH)" -j$(nproc)
	popd
	
	# build u-boot toc
	cp -v $base_path/licheerv_toc1.cfg .
	$${DIR}/tools/mkimage -T sunxi_toc1 -d licheerv_toc1.cfg u-boot.toc1
	cp u-boot.toc1 "$(OUT_DIR)"

	export DIR='u-boot'

	# https://andreas.welcomes-you.com/boot-sw-debian-risc-v-lichee-rv/
	cp -v $(base_path)/bootscr.txt .
	
	$${DIR}/tools/mkimage -T script -C none -O linux -A "$(ARCH)" -d bootscr.txt boot.scr
	rm bootscr.txt
	cp boot.scr "$(OUT_DIR)"

flash:
	dd if="$(OUT_DIR)/boot0_sdcard_sun20iw1p1.bin" of="$(DEVICE)" bs=8192 seek=16
	dd if="$(OUT_DIR)/u-boot.toc1" of="$(DEVICE)" bs=512 seek=32800

install_boot:
	mkdir -p "rootfs/boot/extlinux"
	cp $(base_path)/extlinux.conf "rootfs/boot/extlinux/extlinux.conf"

clean_rootfs:
	pushd rootfs
		if [ x"$(cat boot/latest-config | grep CONFIG_MODULES=y)" = x"CONFIG_MODULES=y" ]; then \
            chroot . /bin/bash -c 'source /etc/profile && update-initramfs -c -k all';\
        else \
            sed -i '/initrd/d' boot/grub.cfg;\
        fi
	popd

	mkdir -p kernel-output
	cp -vr rootfs/boot kernel-output
	if [ -d rootfs/lib/modules ]; then\
        cp -vr rootfs/lib/modules kernel-output;\
    fi

	tar -I zstd -cvf $(DISTURB)-kernel-$(base_path)-$(date +%Y%m%d%H%M%S).tar.zst kernel-output

	rm -rf rootfs/root/*
	umount rootfs/proc rootfs/dev/shm rootfs/dev rootfs/sys rootfs/run
	umount -l rootfs
	losetup -d $(DEVICE)
	export file_name=$(DISTURB)-$(base_path)-$(date +%Y%m%d%H%M%S)
	mv rootfs.img $${file_name}.img
	zstd -T0 --ultra -20 $${file_name}.img
	ls -al .

kernel_build_artifacts:
	path: "$(DISTURB)-kernel-$(base_path)-*.tar.zst"

upload_artifacts:
	path: "$(DISTURB)-*-*.img.zst"