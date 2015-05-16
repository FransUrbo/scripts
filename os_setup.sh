#!/bin/sh

BLOCK_DEV=
TNAME="osinstall-$(date +%s)-$$"
TEMPDIR=/tmp
OS=gentoo

die() {
	echo >&2 "$@"
	exit 1
}

help() {
	echo "Usage: `basename $0` [-b block_device] [-c] [-o os] [-v os_version] [-z zvol]"
	echo "       -b [block_device]   Create pool on [block device]"
	echo "       -o [os]             OS to install [gentoo or debian]"
	echo "       -v [os_version]     OS version/name to install"
	echo "       -z [zvol]           Create a 20GB ZVOL to install on (and create an ext4 fs on)"
	exit 0
}

wait_dev() {
	while [ ! -e "$1" ]; do
		sleep 1
	done
}

[ -z "$1" ] && help

while getopts ":b:o:v:z:" opt; do
	case $opt in
	b)
		[ -n "$ZVOL" ] && die "-b and -z is mutually exclusive"

		BLOCK_DEV="$(readlink -f ${OPTARG})"
		;;
	\?)
		echo "Invalid option: -$OPTARG" >&2
		;;
	:)
		die "Option -$OPTARG requires an argument."
		;;
	h)
		help
                ;;
	o)
		OS=${OPTARG}
                ;;
	v)
		OSVERSION=${OPTARG}
                ;;
	z)
		[ -n "$BLOCK_DEV" ] && die "-b and -z is mutually exclusive."
                [ ! -d "/dev/zvol" ] && die "No /dev/zvol directory, can't create zvol."

		ZVOL=${OPTARG#/dev/zvol/} # Remove /dev/zvol/ just in-case.
                ;;
	esac
done

# Create pool and root filesystem
create_pool_fs() {
	# XXX: It is possible to specify an invalid block device, but it won't appear here due to readlink
	[ -b "${BLOCK_DEV}" ] || die "Invalid block device '${BLOCK_DEV}' specified."

	# Create pool
	zpool create -R ${MOUNTPOINT} -o cachefile=/tmp/zpool.cache -O \
		normalization=formD -m none -t ${TNAME} rpool ${BLOCK_DEV} \
		|| die "Could not create pool"

	# Create rootfs
	zfs create -o mountpoint=none ${TNAME}/ROOT
	zfs create -o mountpoint=/ ${TNAME}/ROOT/$OS

	# Create home directories
	zfs create -o mountpoint=/home ${TNAME}/HOME
	zfs create -o mountpoint=/root ${TNAME}/HOME/root

	# Create portage directories
	zfs create -o mountpoint=none -o setuid=off ${TNAME}/$OS
        if [ "$OS" = "gentoo" ]; then
		zfs create -o mountpoint=/usr/portage -o atime=off ${TNAME}/$OS/portage
		zfs create -o mountpoint=/usr/portage/distfiles ${TNAME}/$OS/distfiles

		# Create portage build directory
		zfs create -o mountpoint=/var/tmp/portage -o compression=lz4 -o sync=disabled ${TNAME}/$OS/build-dir

		# Create optional packages directory
		zfs create -o mountpoint=/usr/portage/packages ${TNAME}/$OS/packages
        fi

	# Create optional ccache directory
	zfs create -o mountpoint=/var/tmp/ccache -o compression=lz4 ${TNAME}/$OS/ccache
}

create_zvol() {
	# Create ZVOL
	zfs create -V20G -s -o primarycache=none -o secondarycache=none -o compression=lz4 -o volblocksize=8K "${ZVOL}"
	[ "$?" -gt 0 ] && die "Couldn't create ZVOL"

	# Wait for device
	wait_dev "/dev/zvol/${ZVOL}"

	# Partition ZVOL device
	parted /dev/zvol/${ZVOL} mklabel msdos
	parted -a optimal /dev/zvol/${ZVOL} <<EOF
unit MB 
mkpart primary ext4 1 100 
mkpart primary linux-swap 100 2048
mkpart primary ext4 2048 100%
set 1 boot on
quit
EOF
	# Wait for first partition
	wait_dev "/dev/zvol/${ZVOL}-part1"

	# Create filesystems on ZVOL device partitions
	mke2fs -j "/dev/zvol/${ZVOL}-part1"
	mkswap -f "/dev/zvol/${ZVOL}-part2"
	mke2fs -j "/dev/zvol/${ZVOL}-part3"

	# Mount ZVOL device
	[ ! -d ${MOUNTPOINT} ] && mkdir -p ${MOUNTPOINT}
        mount -t ext4 "/dev/zvol/${ZVOL}-part3" ${MOUNTPOINT}
	mkdir ${MOUNTPOINT}/boot
	mount -t ext4 "/dev/zvol/${ZVOL}-part1" ${MOUNTPOINT}/boot
}

install_gentoo() {
	# Setup rootfs
	wget 'ftp://gentoo.osuosl.org/pub/gentoo/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-[0-9]*.tar.bz2' \
		|| die "Could not fetch tarball"

	tar -xvjpf stage3-amd64-*.tar.bz2 -C "${MOUNTPOINT}" \
		|| die "Could not extract tarball"

	# Copy resolv.conf into chroot
	cp /etc/resolv.conf "${MOUNTPOINT}/etc/resolv.conf"

	# Use a mount namespace (replaces chroot method)
	unshare -m /bin/bash << END
pivot_root "${MOUNTPOINT}" "${MOUNTPOINT}/mnt"
mount --rbind {/mnt,}/dev
mount --rbind {/mnt,}/sys
mount -t proc none /proc
umount -l /tmp
exec bash
PS1="(${OS}-zfs) $PS1"
cd

# Get portage snapshot (use OSUOSL mirror because it is usually fast)
env GENTOO_MIRRORS="http://gentoo.osuosl.org" emerge-webrsync

# Install genkernel
emerge sys-kernel/genkernel

# Install sources
emerge sys-kernel/gentoo-sources

# Install miscellaneous packages
emerge pkgconf eudev vim htop tmux wgetpaste

# Build initial kernel (required for checks in sys-kernel/spl and sys-fs/zfs)
# FIXME: Make genkernel support modules_prepare
genkernel kernel --makeopts=\""${MAKEOPTS}"\" --no-clean --no-mountboot

# Install ZFS
echo "sys-kernel/spl ~amd64" >> /etc/portage/package.accept_keywords
echo "sys-fs/zfs-kmod ~amd64" >> /etc/portage/package.accept_keywords
echo "sys-fs/zfs ~amd64" >> /etc/portage/package.accept_keywords
emerge sys-fs/zfs

# Add zfs to boot runlevel
rc-update add zfs boot

# Install GRUB2
echo "sys-boot/grub:2 libzfs" >> /etc/portage/package.use
emerge sys-boot/grub:2
touch /etc/mtab
grub2-install "${BLOCK_DEV}"

# Comment the BOOT, ROOT and SWAP lines in /etc/fstab
sed -i -e "s/\(.*\)\/\(BOOT\|ROOT\|SWAP\)\(.*\)/\#\1\/\2\3/g" /etc/fstab

# Setup serial terminals
sed -i -e 's\#s0:12345:respawn:/sbin/agetty -L 115200 ttyS0 vt100\s0:12345:respawn:/sbin/agetty -a root -L 115200 ttyS0 linux\' /etc/inittab 
sed -i -e 's\#s1:12345:respawn:/sbin/agetty -L 115200 ttyS1 vt100\s1:12345:respawn:/sbin/agetty -a root -L 115200 ttyS1 linux\' /etc/inittab

# Configure GRUB2 to boot the system on serial ports
sed -i -e 's:\(#\|\)\(GRUB_TERMINAL=\)\(.*\)$:\2serial\nGRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1":' /etc/default/grub
sed -i -e 's:\(#\|\)\(GRUB_CMDLINE_LINUX_DEFAULT=\)\(.*\)$:\2"console=ttyS0,115200n8":' /etc/default/grub

# We must create an empty configuration file so genkernel finds the right one.
touch /boot/grub/grub.cfg

# Setup a hostid:
printf "$(hostid | sed 's/\([0-9A-F]\{2\}\)/\\x\1/gI')" > /etc/hostid

# Build kernel and initramfs
genkernel all --makeopts=\""${MAKEOPTS}"\" --no-clean --no-mountboot --zfs --bootloader=grub2 --callback="emerge @module-rebuild"
END
}

install_debian() {
	type debootstrap > /dev/null 2>&1 || die "ERROR: command 'debootstrap' is missing"
        [ -z "$OSVERSION" ] && die "-v is required"

	unshare -m /bin/bash << END
debootstrap ${OSVERSION} ${MOUNTPOINT}

pivot_root "${MOUNTPOINT}" "${MOUNTPOINT}/mnt"
mount --rbind {/mnt,}/dev
mount --rbind {/mnt,}/sys
mount -t proc none /proc
umount -l /tmp
exec bash
PS1="(${OS}-zfs) $PS1"
cd

# Install kernel and miscellaneous packages
apt-get -y install linux-image-amd64 lsb-release less

# Install ZFS and GRUB2 packages
wget http://archive.zfsonlinux.org/debian/pool/main/z/zfsonlinux/zfsonlinux_6_all.deb
dpkg -i zfsonlinux_6_all.deb
apt-get update
apt-get -y install debian-zfs grub-common grub-pc grub-pc-bin grub2-common

# Disable systemd
if [ "${OSVERSION}" == "jessie" ]; then
	apt-get -y install sysvinit-core sysvinit sysvinit-utils
	apt-get -y remove --purge --auto-remove systemd
	echo -e 'Package: systemd\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/systemd
	echo -e 'Package: *systemd*\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/systemd
fi

# Install GRUB2 on device/zvol
if [ -d "${BLOCK_DEV}" ]; then
	grub-install "${BLOCK_DEV}"
elif [ -d "${ZVOL}" ]; then
	grub-install "/dev/zvol/${ZVOL}"
fi
END
}

# ---------------------------------------------------------

# Create pool+filesystem or zvol.
MOUNTPOINT="${TEMPDIR}/${TNAME}"
if [ -n "$BLOCK_DEV" ]; then
	create_pool_fs
elif [ -n "$ZVOL" ]; then
	create_zvol
fi

# Do the install
cd "${MOUNTPOINT}"
func=$(eval echo install_$OS)
type $func > /dev/null 2>&1 || die "ERROR: Unsupported OS"
$func

# Cleanup (snapshot, export/unmount install dir etc)
cd ${OLDPWD}
if [ -n "$BLOCK_DEV" ]; then
	zfs snapshot ${TNAME}@install
	zpool export ${TNAME}

	echo "New $OS ZFS system installed on ${BLOCK_DEV}"
elif [ -n "$ZVOL" ]; then
        umount ${MOUNTPOINT}/boot
        umount ${MOUNTPOINT}
	zfs snapshot ${ZVOL}@install

	echo "New $OS ZFS system installed on ${ZVOL}"
fi
