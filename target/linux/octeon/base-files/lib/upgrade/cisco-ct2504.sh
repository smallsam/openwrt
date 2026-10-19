# Cisco AIR-CT2504-K9 helpers for sysupgrade.
#
# The boot loader keeps its image files (linux.{pri,bak}.img and
# cavium_main.{pri,bak}) on partition 2 of the CompactFlash card. OpenWrt
# is installed in the secondary slot: the kernel is linux.bak.img, the
# replacement for the vendor's data plane application cavium_main.bak, and
# the root file system lives on partition 4, which the vendor software does
# not use (see cisco-ct2504.md).

CT2504_CF_DEVICE=12000000.compact-flash
CT2504_IMAGES_PART=2
CT2504_IMAGES_FSTYPE=ext4
CT2504_ROOT_PART=4

ct2504_get_disk() {
	local partnum=$1
	local uevent

	uevent=$(find /sys/bus/platform/devices/${CT2504_CF_DEVICE}/ \
		-path \*block/sd[a-z]/uevent | sed -n 1p)
	[ -n "$uevent" ] || return 1

	echo "/dev/$(sed -n 's/^DEVNAME=//p' "$uevent")${partnum}"
}

# platform_do_upgrade: kernel and data plane replacement to the image
# partition, root file system to its partition.
ct2504_do_upgrade() {
	local tar_file="$1"
	local board_dir images rootfs

	board_dir=$(tar tf "$tar_file" | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}
	[ -n "$board_dir" ] || return 1

	images="$(ct2504_get_disk $CT2504_IMAGES_PART)" || return 1
	rootfs="$(ct2504_get_disk $CT2504_ROOT_PART)" || return 1
	[ -b "$images" ] && [ -b "$rootfs" ] || return 1

	mkdir -p /boot
	mount -t $CT2504_IMAGES_FSTYPE "$images" /boot || return 1

	echo "flashing kernel to linux.bak.img"
	tar xf "$tar_file" $board_dir/kernel -O > /boot/linux.bak.img.new
	echo "flashing data plane replacement to cavium_main.bak"
	tar xf "$tar_file" $board_dir/cavium_main -O > /boot/cavium_main.bak.new
	sync
	mv /boot/cavium_main.bak.new /boot/cavium_main.bak
	mv /boot/linux.bak.img.new /boot/linux.bak.img
	umount /boot

	echo "flashing rootfs to $rootfs"
	tar xf "$tar_file" $board_dir/root -O | dd of="$rootfs" bs=4096
	sync
}
