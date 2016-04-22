#!/bin/bash

# Script to do a full inventory of all disks in the system.
# Copyleft: Turbo Fredriksson <turbo@bayour.com>
# Released under the GPL (version of your choosing).

# The following commands improve output, but is not required:
#   zpool, pvs, cryptsetup, bc, lshw
# 
# The following command is not required, but they should really
# exist for best usage:
#   lsscsi, fdisk, smartctl
# 
# The following command is required (won't work without it!):
#   lspci, tempfile, getopt, basename, grep, find, cat, ls,
#   mount, readlink
#
# Extra information is stored in the following files (script will
# ignore any line that starts with a dash - #):
#   $HOME/.disks
#       Columns: Model, Serial, Enclosure, Slot - separated by tabs
#       Example:
#
#       # Model		Serial			Enclosure	Slot	Rev	Warranty	Device
#       ST31500341AS	9VS4XK4T		4		1	CC1H	20140112	sdf
#       ST31500341AS	9VS3SAWS		4		3	CC1H	+		sdh
#
#   For me, a '+' means that the warranty have expired. This can be any
#   character, just remember what means what.

[ "$USER" != "root" ] && \
    echo "WARNING: This script really needs to run with root privilegues." \
    > /dev/stderr

# Need a temp file to store variables inside while loops
# which we need at the very end.
DSK_TEMP=$(tempfile -d /tmp -p dsk.)

# --------------
# Set/figure out default output information
DO_ZFS=0
if type zpool > /dev/null 2>&1; then
    DO_ZFS=1
    ZFS_TEMP=$(tempfile -d /tmp -p zfs.)

    if [ $(zpool status 2>&1 | egrep -v '^no pools' | tee $ZFS_TEMP | wc -l) -lt 1 ]; then
	rm $ZFS_TEMP
	DO_ZFS=0
    fi
fi

DO_LVM=0
if type pvs > /dev/null 2>&1; then
    DO_LVM=1
    LVM_TEMP=$(tempfile -d /tmp -p lvm.)

    if [ $(pvs --noheadings --nosuffix --separator , | tee $LVM_TEMP | wc -l) -lt 1 ]; then
	rm $LVM_TEMP
	DO_LVM=0
    fi
fi

DO_MD=0
[ -f "/proc/mdstat" ] && DO_MD=1

if type cryptsetup > /dev/null 2>&1; then
    if [ -d /dev/mapper ]; then
	DO_DMCRYPT=1			# Look for crypted disks?
	DMCRYPT=""			# List of crypted devices:real dev
	CRYPTED_HAVE_BEEN_SEEN=""	# Have we found any crypted disks?

	for dev_path in /dev/mapper/*; do
	    [ "$dev_path" == "/dev/mapper/control" ] && continue

	    name=$(basename "$dev_path")
	    dev=$(cryptsetup status $name | grep device: | sed 's@.*/@@')

	    if [ -n "$name" -a -n "$dev" ]; then
		DMCRYPT="$DMCRYPT $name:$dev"
	    fi
	done
    else
	DO_DMCRYPT=0
    fi
fi

DO_LOCATION=0
DO_WARRANTY=0
if [ -f $HOME/.disks ]; then
    DO_LOCATION=1
    DO_WARRANTY=1
fi

DO_VDEV_ALIAS=0
[ -d /dev/disk/by-vdev ] && DO_VDEV_ALIAS=1

TEMP_FILE=$(tempfile -d /tmp -p dsk.)
DO_REV=1 ; DO_MACHINE_READABLE=0 ; DO_WWN=0 ; DO_SERIAL=1

# --------------
# Get the CLI options - override DO_* above...
TEMP=$(getopt -o h --long no-zfs,no-lvm,no-md,no-dmcrypt,no-location,no-warranty,no-rev,no-serial,help,machine-readable,use-wwn -- "$@")
eval set -- "$TEMP"
while true ; do
    case "$1" in
	--no-zfs)		DO_ZFS=0		; shift ;;
	--no-lvm)		DO_LVM=0		; shift ;;
	--no-md)		DO_MD=0			; shift ;;
	--no-dmcrypt)		DO_DMCRYPT=0		; shift ;;
	--no-location)		DO_LOCATION=0		; shift ;;
	--no-warranty)		DO_WARRANTY=0		; shift ;;
	--no-rev)		DO_REV=0		; shift ;;
	--no-serial)		DO_SERIAL=0		; shift ;;
	--no-vdev-alias)	DO_VDEV_ALIAS=0		; shift ;;
	--machine-readable)	DO_MACHINE_READABLE=1	; shift ;;
	--use-wwn)		DO_WWN=1		; shift ;;
	--help|-h)
	    echo "Usage: `basename $0` [--no-zfs|--no-lvm|--no-md|--no-dmcrypt|--no-location|--no-warranty|--no-rev|--no-serial|--no-vdev-alias|--machine-readable|--use-wwn]"
	    echo
	    exit 0
	    ;;
	--)			shift			; break ;;
	*)			echo "Internal error!"	; exit 1 ;;
    esac
done

# --------------
# Output header
if [ "$DO_MACHINE_READABLE" == 1 ]; then
    echo -n "CTRL;Host;"
    [ "$DO_LOCATION" == 1 ] && echo -n "PHY;"
    echo -n "Name;ataXX;"
    [ "$DO_VDEV_ALIAS" == 1 ] && echo -n "VDEV_ALIAS;"
    echo -n "Model;"
    if [ "$DO_WWN" == 0 ]; then
	echo "Device by ID;"
    else
	echo "Device by WWN;"
    fi
    [ "$DO_REV" == 1 ] && echo -n "Rev;"
    [ "$DO_SERIAL" == 1 ] && echo -n "Serial;"
    [ "$DO_WARRANTY" == 1 ] && echo -n "Warranty;"
    echo -n "Family;"
    [ "$DO_MD" == 1 ] && echo -n "MD;"
    [ "$DO_LVM" == 1 ] && echo -n "VG;"
    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]  && echo -n "DM-CRYPT;"
    [ "$DO_ZFS" == 1 ] && echo -n "ZFS;"
    echo "Mount Point;"
    echo "Size"
else
    printf "  %-15s" "Host" 
    [ "$DO_LOCATION" == 1 ] && printf "%-4s" "PHY"
    printf " %-6s %-10s" "Name" "ataXX"
    [ "$DO_VDEV_ALIAS" == 1 ] && printf "%-15s" "VDEV Alias"
    printf " %-20s" "Model"
    if [ "$DO_WWN" == 0 ]; then
	printf "%-45s" "Device by ID"
    else
	printf "%-45s" "Device by WWN"
    fi
    [ "$DO_REV" == 1 ] && printf "%-10s" "Rev"
    [ "$DO_SERIAL" == 1 ] && printf "%-25s" "Serial"
    [ "$DO_WARRANTY" == 1 ] && printf "%-10s" "Warranty"
    printf "%-30s" "Family"
    [ "$DO_MD" == 1 ] && printf "%-10s" "MD"
    [ "$DO_LVM" == 1 ] && printf "%-10s" "VG"
    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]  && printf "%-25s" "DM-CRYPT"
    [ "$DO_ZFS" == 1 ] && printf "%-30s" "  ZFS"
    printf "%-20s" "Mount Point"
    printf "%8s\n\n" "Size"
fi

# --------------
get_udev_info () {
    key=$1
    val=$(grep "$key=" $TEMP_FILE | sed 's@.*=@@')
    if [ -z "$val" ]; then
	echo "n/a"
    else
	echo "$val"
    fi
}

# --------------
declare -A DISK
load_lshw_info () {
    type lshw > /dev/null 2>&1 || return

    local dev
    declare -A disk

    while read line; do
	# New disk!
	echo "${line}" | grep -Eq "^*-disk:.*[0-9]$" && disk=""

	if echo "${line}" | grep -Eq "^description: "; then
	    disk[description]="${line##description: }"
	elif echo "${line}" | grep -Eq "^product: "; then
	    disk[product]="${line##product: }"
	elif echo "${line}" | grep -Eq "^vendor: "; then
	    disk[vendor]="${line##vendor: }"
	elif echo "${line}" | grep -Eq "^physical id: "; then
	    disk[physical_id]="${line##physical id: }"
	elif echo "${line}" | grep -Eq "^bus info: "; then
	    disk[bus_info]="${line##bus info: }"
	elif echo "${line}" | grep -Eq "^logical name: "; then
	    disk[logical_name]="${line##logical name: }"
	elif echo "${line}" | grep -Eq "^version: "; then
	    disk[version]="${line##version: }"
	elif echo "${line}" | grep -Eq "^serial: "; then
	    disk[serial]="${line##serial: }"
	elif echo "${line}" | grep -Eq "^size: "; then
	    disk[size]="$(echo "${line}" | sed "s,size: \(.*\) .*,\1,")"
	elif echo "${line}" | grep -Eq "^capabilities: "; then
	    disk[capabilities]="${line##capabilities: }"
	elif echo "${line}" | grep -Eq "^configuration: "; then
	    disk[configuration]="${line##configuration: }"
	fi

	dev="${disk[logical_name]}"
	[ -z "${dev}" ] && continue

	if [ -n "${disk[description]}"   -a -n "${disk[product]}" -a \
	     -n "${disk[vendor]}"        -a -n "${disk[physical_id]}" -a \
	     -n "${disk[bus_info]}"      -a -n "${disk[logical_name]}" -a \
	     -n "${disk[version]}"       -a -n "${disk[serial]}" -a \
	     -n "${disk[size]}"          -a -n "${disk[capabilities]}" -a \
	     -n "${disk[configuration]}" -a -z "${DISK[${dev}]}" ]
	then
	    DISK[${dev}]="${dev}:${disk[vendor]}:${disk[product]}:${disk[version]}:${disk[serial]}:${disk[size]}"
	fi
    done <<EOF
$(lshw -class disk 2> /dev/null)
EOF
}
load_lshw_info

get_lshw_info () {
    local val="$1"
    local dev="$2"

    IFS=":"
    set -- $(echo "${DISK[$dev]}")

    if [ "${val}" == "vendor" ]; then
	echo "$2"
    elif [ "${val}" == "product" ]; then
	echo "$3"
    elif [ "${val}" == "version" ]; then
	echo "$4"
    elif [ "${val}" == "serial" ]; then
	echo "$5"
    elif [ "${val}" == "size" ]; then
	echo "$6"
    fi
}

# --------------
load_lshw_info # Initialize the DISK array.

# MAIN function - get a list of all PCI devices, extract storage devices.
PCI_DEVS=$(tempfile -d /tmp -p pci.)
lspci -D > $PCI_DEVS

(cat $PCI_DEVS | grep -E 'SATA|IDE'  ; \
 cat $PCI_DEVS | grep -E 'SCSI|RAID' ; \
 cat $PCI_DEVS | grep -E 'FireWire|IEEE' ; \
 cat $PCI_DEVS | grep -E 'USB' | grep -v OHCI) | \
    sort | uniq | \
    while read line; do
	ctrl_id=${line%% *}

	# --------------
	# What type is this - ata/ide or scsi/sata
	if [[ $line =~ SATA|SCSI|RAID ]]; then
	    if [[ $line =~ 'IDE mode' ]]; then
		type=ata
	    else
		type=scsi
	    fi
	elif [[ $line =~ USB ]]; then
	    type=usb
	else
	    type=ata
	fi

	if [ "$DO_MACHINE_READABLE" == 1 ]; then
	    ctrl="$line"
	else
	    echo "$line"
	fi

	# --------------
	# First while, just to sort '.../host2' before '.../host10'.
	find /sys/bus/pci/devices/$ctrl_id/{host*,ide*,ata*,cciss*,usb[0-9]*,fw[0-9]*} -maxdepth 0 2> /dev/null | \
	    while read path; do
		host=${path/*host/}
		host=${host/*ide/}
		host=${host/*ata/}
		host=${host/*cciss/}
		host=${host/*usb/}
		host=${host/*fw/}
		printf "host%0.2d;$path\n" "$host"
	    done | \
	    sort | \
		while read path; do
		    path=${path/*;/}
		    got_hosts= ; chk_ata=

		    # ----------------------
		    # Get HOST name
		    if [ -d $path/host* ]; then
			host=$(echo $path/host* | sed 's@.*/@@')
		    else
			host=${path/*\//}
		    fi

		    # ----------------------
		    # Make sure this host actually have devices attached.
		    got_hosts=$(find "$path/.." -maxdepth 1 -type d -name 'host*')
		    [[ $host =~ ^ata ]] && chk_ata=${BASH_REMATCH}
		    [ -n "$got_hosts" -a -n "$chk_ata" ] && continue

		    # ----------------------
		    # Get block device path(s)
		    if find $path/phy-* -maxdepth 0 > /dev/null 2>&1; then
			blk_devs=$(find $path/phy-* -name phy_identifier 2> /dev/null | sort)
		    else
			blk_devs=$(find $path -name rev 2> /dev/null | sort)
		    fi

		    # ----------------------
		    if [ -n "$blk_devs" ]; then
			echo "$blk_devs" |
			    while IFS=" " read dev; do
				# Reset path variable to actual/full path for this device
				l=$(readlink -f "$dev")
				path=${l%/*}     # dirname $l

				# Catch empty ports on a SAS card
				if [[ $path =~ /phy-*:? ]]; then
				    # path='/sys/devices/pci0000:00/0000:00:02.0/0000:01:00.0/host0/phy-0:0/sas_phy/phy-0:0'

				    if [[ -e "$path/device/port" ]]; then
					# Port have attached device

					rev=$(find $path/device/port/ -name 'rev')
					if [ -z "$rev" ]; then
					    # SOMETHING is connected here, but we can't figure out what..
					    # This happened to me when the SAS chain kicked a disk.
					    # => Simulate 'empty port'.
					    host=$(echo $path | sed 's@.*/phy-\([0-9]\+\):\([0-9]\+\)/.*@host\1:\2@')
					    [ "$DO_MACHINE_READABLE" == 0 ] && printf "  %-15s\n" $host

					    continue
					fi

					# rev='/sys/devices/pci0000:00/0000:00:02.0/0000:01:00.0/host0/phy-0:0/sas_phy/phy-0:0/device/port/end_device-0:0/target0:0:0/0:0:0:0/rev'

					host=$(echo "$rev" | sed 's@.*/phy-\([0-9]\+\):\([0-9]\+\)/.*@host\1:\2@')

					t=${rev%/*} # remove file part
					t_id=${t##*/}
				    else
					# Empty port
					host=$(echo $path | sed 's@.*/phy-\([0-9]\+\):\([0-9]\+\)/.*@host\1:\2@')
					[ "$DO_MACHINE_READABLE" == 0 ] && printf "  %-15s\n" $host

					continue
				    fi
				elif [[ $path =~ /port-*:? ]]; then
				    # path='/sys/devices/pci0000:00/0000:00:0b.0/0000:03:00.0/host0/port-0:0/end_device-0:0/target0:0:0/0:0:0:0'
				    host=$(echo "$path" | sed "s@.*/.*\(host[0-9]\+\)/port-\([0-9]\+\):\([0-9]\+\)/.*@\1:\3@")
				    t_id=${path##*/} # basename "$path"
				elif [[ $path =~ usb ]]; then
				    # path=/sys/devices/pci0000:00/0000:00:13.2/usb6/6-2/6-2:1.0/host8/target8:0:0/8:0:0:0
				    host=$(echo $path | sed "s@.*/usb\([0-9]\+\)/[0-9]-\([0-9]\)/.*@usb\1:\2@") # => usb6:2

				    t_id=${path##*/} # basename "$path"
				else
				    t_id=${path##*/} # basename "$path"
				fi

				# ----------------------
				# Get name
				name=
				if [[ $t_id =~ ^[0-9] ]] && type lsscsi > /dev/null 2>&1; then
				    lsscsi_out=$(lsscsi --device "$t_id")
				    if ! echo "$lsscsi_out" | grep -Eqi 'disk|dvd|cd|tape'; then
					continue
				    fi

				    name=$(echo "$lsscsi_out" | sed -e 's@.*/@@' -e 's@ \[.*@@' -e 's@\[.*@@')
				fi
				if [ -z "$name" -o "$name" == "-" ] && [ -n "$t_id" ]; then
				    # /sys/block/*/device | grep '/0000:05:00.0/host8/'
				    name=$(ls -ln /sys/block/*/device | \
					grep "/$t_id" | sed -e "s@.*block/\(.*\)/device .*@\1@")
				    if [ -z "$name" ]; then
					name="n/a"
				    fi
				fi

				# ----------------------
				# Try to map the device name to the kernel 'ataXX' message.
                                # The 'correct' way.
				ataXX=$(readlink /sys/block/$name | sed "s@.*\(ata[0-9]\+\).*@\1@")
                                if echo "$ataXX" | grep -q /; then
				    # SAS devices don't have a 'ataXX' name in the path.
				    # Try the more complicated way
                                    # NOTE: A usb stick doesn't get a 'ataXX' unit. But still
                                    #       catch this. Hopefully "idProduct=5571" IS a USB
                                    #       stick!
				    ataXX=$((cat /var/log/dmesg ; dmesg) | \
                                        egrep 'ata[0-9].*: ATA-|usb .*: New USB device found.*idProduct=5571' | \
					sed -e "s@.*ata\([0-9]\+\.[0-9]\+\).*@\1@" -e "s@.* usb \([0-9]-[0-9]\): .*@usb\1@" | \
					awk '{ a=$1; printf("%s is /dev/sd%c\n", a, 96+NR); }' |\
					grep "/$name\$" | sed 's@ .*@@')
                                fi

				# ----------------------
				# Get all info availible for $name
				if [ -n "$name" -a "$name" != "n/a" ]; then
				    udevadm info -q all -p /sys/block/$name > $TEMP_FILE
				fi

				# ----------------------
				# Get vdev alias
				vdev_alias=
				set -- `ls -l /dev/disk/by-vdev/ | grep -E "/$name\$"`
				vdev_alias="$9"

				# ----------------------
				# Get dev path
				dev_path=$(get_udev_info DEVNAME)

				# ----------------------
				# Get model
				t=$(get_udev_info ID_MODEL)
				model=${t/-*/}

				# ----------------------
				# Get and revision
				[ "$DO_REV" == 1 ] && rev=$(get_udev_info ID_REVISION)

				# ----------------------
				# Get serial number
				if [ "$DO_SERIAL" == 1 ]; then
				    serial=$(get_udev_info ID_SCSI_SERIAL)
				    [ "$serial" == "n/a" ] && serial=$(get_udev_info ID_SERIAL_SHORT)
				fi

				# ----------------------
				# Get device name (Disk by ID)
				if [ "$DO_WWN" == 1 ]; then
				    device_id=$(get_udev_info ID_WWN)
				else
				    device_id="n/a"
				fi
				[ "$device_id" == 'n/a' ] && device_id=$(get_udev_info ID_SCSI_COMPAT)
				[ "$device_id" == 'n/a' ] && device_id=$(get_udev_info ID_ATA_COMPAT)
				if [ "$device_id" == 'n/a' -a -n "$dev_path" -a "$dev_path" != "n/a" ] \
					&& type smartctl > /dev/null 2>&1
				then
				    # No match. Let's try smartctl instead then. Unfortunatly, the type
				    # of info isn't availible 'as is', so we have to wing it a little.
				    set -- $(smartctl -a $dev_path | grep -E '^Device Model:|^Serial Number:' | \
					sed -e "s@.* \(.*\).*@\1@" -e "s@-.*@@")
				    if [ -n "$1" -a -n "$2" ]; then
					device_id=$(/bin/ls -l /dev/disk/by-id/$type*$1*$2 | sed "s@.*$type-\(.*\) -.*@\1@")
				    fi
				fi
				if [[ "$device_id" == 'n/a' ]]; then
				    # One last attempt!
				    device_id=$(/bin/ls -l /dev/disk/by-id/ | \
					grep -E "/$name$" | \
					sed -e "s@.*usb-\(.*\) -.*@\1@" \
					    -e "s@.*ata-\(.*\) -.*@\1@")
				fi

				# ----------------------
				# Get DM-CRYPT device mapper name
				dmcrypt='n/a'
				if [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]; then
				    for dm_dev_name in $DMCRYPT; do
					set -- ${dm_dev_name//:/ }
					dm_name=$1
					dm_dev=${2/[0-9]/}
					[[ $device_id =~ $dm_dev ]] && dmcrypt=${BASH_BASH_REMATCH}
					[ "$name" == "$dm_dev" ] && dmcrypt=$dm_name
				    done
				fi

				# ----------------------
				# Get MD device
				md='n/a'
				if [ "$DO_MD" == 1 ]; then
				    MD=$(grep $name /proc/mdstat | sed 's@: active raid1 @@')
				    if [ -n "$MD" ]; then
					# md3 sdg1[0] sdb1[1]
					set -- $(echo "$MD")
					for dev in $*; do
					    dev=${dev//\[?\]/}

					    md=$1
#					    if [[ $dev =~ ^$name(.*) ]]; then
#						# md11 : active raid1 sde3[0]
#						# md10 : active raid1 sde1[0]
#						# => md111
#						#md=$1${BASH_REMATCH[1]}
#						echo "md(1)='$md' ($BASH_REMATCH)"
#					    elif [[ $dev =~ ^$name ]]; then
#						md="$1"
#						break
#					    fi
					done
				    fi
				fi

				# ----------------------
				# Get LVM data (VG - Virtual Group) for this disk
				vg='n/a'
				if [ "$DO_LVM" == 1 ]; then
				    lvm_regexp="/$name"
				    if [ -n "$md" -a "$md" != "n/a" ]; then
					lvm_regexp="$lvm_regexp|"${md//\(?\)/}
				    fi

				    vg=$(cat $LVM_TEMP |
					while read pvs; do
					    dm= ; dev=
					    if [[ $pvs =~ /dm- && "$DO_DMCRYPT" == 1 ]]; then
						dm=${pvs//,*/}
						dev=/$(cryptsetup status $dm | grep device: | sed -e 's@.*/@@' -e 's@[0-9]$@@')
					    fi
					    if [[ $pvs =~ $lvm_regexp || $dev =~ $lvm_regexp ]]; then
						echo "$pvs" | sed "s@.*,\(.*\),lvm.*@\1@"
					    fi
					done)
				    if [ -z "$vg" -a "$md" != "n/a" ]; then
					# Double check - is it mounted
					vg=$(mount | grep "/$md" | sed "s@.* on \(.*\) type.*@\1@")
				    fi
				    [ -z "$vg" ] && vg='n/a'
				fi

				# ----------------------
				# Get ZFS pool data for this disk ID
				if [ "$DO_ZFS" == 1 ]; then
				    zfs_regexp=

				    # OID: SATA_Corsair_Force_311486508000008952122
				    # ZFS: ata-Corsair_Force_3_SSD_11486508000008952122
				    tmpnam=${device_id/SATA_/}
				    [ -z "$tmpnam" ] && tmpnam="n/a"

				    # Setup a matching string.
				    # grep -E matches _every line_ if 'NULL|sda|NULL'!
				    [ "$device_id" != 'n/a' ] && zfs_regexp="$device_id"
				    if [ "$name" != 'n/a' ]; then
					if [ -n "$zfs_regexp" ]; then
					    zfs_regexp="$zfs_regexp|$name"
					else
					    zfs_regexp="$name"
					fi
				    fi
				    if [ "$tmpnam" != 'n/a' ]; then
					if [ -n "$zfs_regexp" ]; then
					    zfs_regexp="$zfs_regexp|$tmpnam"
					else
					    zfs_regexp="$tmpnam"
					fi
				    fi
				    if [ "$DO_DMCRYPT" == 1 -a "$dmcrypt" != 'n/a' ]; then
					if [ -n "$zfs_regexp" ]; then
					    zfs_regexp="$zfs_regexp|$dmcrypt"
					else
					    zfs_regexp="$dmcrypt"
					fi
				    fi
				    if [ "$DO_LVM" == 1 -a "$vg" != 'n/a' ]; then
					if [ -n "$zfs_regexp" ]; then
					    zfs_regexp="$zfs_regexp|$vg"
					else
					    zfs_regexp="$vg"
					fi
				    fi
				    if [ "$model" != 'n/a' -a "$serial" != 'n/a' ]; then
					zfs_regexp="$zfs_regexp|$model-.*_$serial"
				    fi
				    if [ -n "$vdev_alias" ]; then
					zfs_regexp="$zfs_regexp|$vdev_alias"
				    fi

				    # Make sure we only match the whole word (not 'test2' if searching for/with 'test').
				    orig_zfs_regexp=$zfs_regexp
				    [[ $zfs_regexp =~ \| ]] && zfs_regexp="($zfs_regexp)"
				    zfs_regexp=\\b$zfs_regexp\\b

				    # What exactly is a VDEV?
				    vdev_regexp="^	  [a-zA-Z0-9]|raid|mirror|cache|spare"

				    zfs=$(cat $ZFS_TEMP | 
					while IFS= read zpool; do # IFS => need the leading spaces
					    offline="" ; crypted=" " ; stat=""

					    # Base values
					    if [[ $zpool =~ 'pool: ' ]]; then
						zfs_name=${zpool/*: /}
						continue
					    elif [[ $zpool =~ 'state: ' ]]; then
						zfs_state=${zpool/*: /}
						# Skip to the interesting bits
						while read zpool; do
						    if [[ $zpool =~ NAME.*STATE.*READ.*WRITE.*CKSUM ]]; then
							continue 2
						    fi
						done

					    # VDEV type
					    elif [[ $zpool =~ raid|mirror|cache|spare ]]; then
						zpool=${zpool#"${zpool%%[![:space:]]*}"} # Strip leading spaces
						zfs_vdev=${zpool/ */}

						if [[ ! $zfs_vdev =~ raid|mirror|cache|spare
							&& $zpool =~ $zfs_regexp
							&& -n "$zfs_name"
							&& -n "$zfs_vdev" ]]
						then
						    if [[ "$device_id" == "${zfs_vdev##$type\-}" ]]; then
							# Oups, no! This is a VDEV with the dev only
							#        NAME                                  STATE     ...
							#        test1                                 ONLINE    ...
							#          scsi-SATA_ST3000DM001-1CH_Z1F46X7A  ONLINE    ...
							printf "$crypted %-17s$stat" "$zfs_name"
						    else
							printf "$crypted %-17s$stat" "$zfs_name / $zfs_vdev"
						    fi
						    break
						fi
					    elif [[ $zpool =~ replacing ]]; then
						replacing="rpl"$(echo "$zpool" | sed "s@.*-\([0-9]\+\) .*@\1@")
						echo 'replacing=1' >> "${DSK_TEMP}"
						ii=1
						continue

					    # DEV
					    elif [[ $zpool =~ $zfs_regexp ]]; then
						# Device status
						if [[ ! $zpool =~ ONLINE|AVAIL ]]; then
						    offline="!"
						    if [[ $zpool =~ OFFLINE ]]; then
							offline="$offline"O
							echo 'offline_type=O' >> "${DSK_TEMP}"
						    elif [[ $zpool =~ UNAVAIL ]]; then
							offline="$offline"U
							echo 'offline_type=U' >> "${DSK_TEMP}"
						    elif [[ $zpool =~ FAULTED ]]; then
							offline="$offline"F
							echo 'offline_type=F' >> "${DSK_TEMP}"
						    elif [[ $zpool =~ REMOVED ]]; then
							offline="$offline"R
							echo 'offline_type=R' >> "${DSK_TEMP}"
						    fi
						elif [[ $zpool =~ resilvering ]]; then
						    offline="$offline"rs
						    echo 'resilvering=1' >> "${DSK_TEMP}"
						fi

						if [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]; then
						    if [[ -n "$tmpdmname" && $zpool =~ $tmpdmname ]]; then
							crypted="*"
							echo 'have_dmcrypted=1' >> "${DSK_TEMP}"
						    fi
						fi

						if [ -n "$replacing" -a -n "$offline" ]; then
						    stat="$replacing"+"$offline"
						elif [ -n "$replacing" -a -z "$offline" ]; then
						    stat="$replacing"
						elif [ -z "$replacing" -a -n "$offline" ]; then
						    stat="$offline"
						fi

						if [ -n "$zfs_name" -a -n "$zfs_vdev" ]; then
						    printf "$crypted %-17s$stat" "$zfs_name / $zfs_vdev"
						fi
					    fi

					    if [ "$ii" == 3 ]; then
						replacing=""
						ii=0
					    else
						ii=$[ $ii + 1 ]
					    fi
					done)
				    [ -z "$zfs" ] && zfs="  n/a"
				fi

				# ----------------------
				# Get mountpoint
				regexp=$orig_zfs_regexp
				if [ -n "$md" -a "$md" != "n/a" ]; then
				    if [ -n "$regexp" ]; then
					regexp="$regexp|$md"
				    else
					regexp="$md"
				    fi
				fi
				if [ -n "$vg" -a "$vg" != "n/a" ]; then
				    regexp="$regexp|/mapper/$vg"
				fi
				if [ -n "$zfs" -a "$zfs" != "n/a" ]; then
				    tmp=${zfs#"${zfs%%[![:space:]]*}"} # Strip leading spaces

				    # share2 on /share type zfs (rw,nosuid,noexec,noatime,noxattr,noacl)
				    # share2 on /share@ type zfs (rw,nosuid,noexec,noatime,noxattr,noacl)
				    regexp="$regexp|^${tmp%% *} .* zfs | /${tmp%% *} .* zfs "
				fi

				if [ -n "$regexp" ]; then
				    set -- $(mount | grep -E "($regexp)")
				    if [ -n "$3" ]; then
					mntpt="$3 ($5)"
				    else
					mntpt="n/a"
				    fi
				else
				    mntpt="n/a"
				fi

				# ----------------------
				# Get size of disk
				if type fdisk > /dev/null 2>&1; then
				    if [ -n "$dev_path" ]; then
					size=$(fdisk -l $dev_path 2> /dev/null | \
					    grep '^Disk /' | \
					    sed -e "s@.*: \(.*\), .*@\1@" \
					    -e 's@\.[0-9] @@' -e 's@ @@g')
					if [[ $size =~ ^[0-9][0-9][0-9][0-9]GB ]] && type bc > /dev/null 2>&1; then
					    s=${size/GB/}
					    size=$(echo "scale=2; $s / 1024" | bc)"TB"
					elif [[ $size =~ ^[0-9][0-9][0-9][0-9]MB ]] && type bc > /dev/null 2>&1; then
					    s=${size/MB/}
					    size=$(echo "scale=2; $s / 1024" | bc)"GB"
					fi
				    fi
				fi
				if [ -z "$size" ]; then
				    size="n/a"
				fi

				# ----------------------
				# Get model family
				family=""
				set -- $(smartctl -a $dev_path | grep -E '^Model Family:' | 
					sed -e "s@.*  \(.*\)@\1@" -e 's@ (.*@@' \
					    -e 's@ [0-9].*@@' -e 's@/.*@@')
				if [ -n "$*" ]; then
				    family="$*"
				else
				    family="$(get_lshw_info "vendor" "$dev_path")"
				fi

				# ----------------------
				# Get warranty information
				if [ "$DO_WARRANTY" == 1 ]; then
				    if [[ $model =~ " " ]]; then
					tmpmodel=${model// /}
				    else
					tmpmodel="$model"
				    fi

				    set -- $(grep -E -w "^$tmpmodel.*$serial" ~/.disks)
				    if [ -n "$6" ]; then
					warranty="$6"
				    else
					warranty="n/a"
				    fi
				else
				    warranty="n/a"
				fi

				# ----------------------
				# Get physical location
				if [ "$DO_LOCATION" == 1 ]; then
				    if [[ $model =~ " " ]]; then
					tmpmodel=${model// /}
				    else
					tmpmodel="$model"
				    fi

				    set -- $(grep -E -w "^$tmpmodel.*$serial" ~/.disks)
				    if [ -n "$3" -a -n "$4" ]; then
					location="$3:$4"
				    else
					location="n/a"
				    fi
				else
				    location="n/a"
				fi

				# ======================
				# Output information
				if [ "$DO_MACHINE_READABLE" == 1 ]; then
				    echo -n "$ctrl;$host;"
				    [ "$DO_LOCATION" == 1 ] && echo -n "$location;"
				    echo -n "$name;$ataXX"
				    [ "$DO_VDEV_ALIAS" == 1 ] && echo -n "$vdev_alias;"
				    echo -n "$model;$device_id;"
				    [ "$DO_REV" == 1 ] && echo -n "$rev;"
				    [ "$DO_SERIAL" == 1 ] && echo -n "$serial;"
				    [ "$DO_WARRANTY" == 1 ] && echo -n "$warranty;"
				    echo -n "$family;"
				    [ "$DO_MD" == 1 ] && echo -n "$md;"
				    [ "$DO_LVM" == 1 ] && echo -n "$vg;"
				    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ] && echo -n "$dmcrypt;"
				    [ "$DO_ZFS" == 1 ] && echo -n "$zfs;"
				    echo "$mntpt;"
				    echo "$size"
				else
				    printf "  %-15s" "$host"
				    [ "$DO_LOCATION" == 1 ] && printf "%-4s" "$location"
				    printf " %-6s %-10s" "$name" "$ataXX"
				    [ "$DO_VDEV_ALIAS" == 1 ] && printf "%-15s" "$vdev_alias"
				    printf " %-20s%-45s" "$model" "$device_id"
				    [ "$DO_REV" == 1 ] && printf "%-10s" "$rev"
				    [ "$DO_SERIAL" == 1 ] && printf "%-25s" "$serial"
				    [ "$DO_WARRANTY" == 1 ] && printf "%-10s" "$warranty"
				    printf "%-30s" "$family"
				    [ "$DO_MD" == 1 ] && printf "%-10s" "$md"
				    [ "$DO_LVM" == 1 ] && printf "%-10s" "$vg"
				    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ] && printf "%-25s" "$dmcrypt"
				    [ "$DO_ZFS" == 1 ] && printf "%-30s" "$zfs"
				    printf "%-20s" "$mntpt"
				    printf "%8s\n" "$size"
				fi
			    done # => 'while read block; do'
		    else
			if [ "$DO_MACHINE_READABLE" == 0 ]; then
			    printf "  %-15s\n" $host
			fi
		    fi
		done # => 'while read path; do'

	[ "$DO_MACHINE_READABLE" == 0 ] && echo
    done

if [ "$DO_MACHINE_READABLE" == 0 ]; then
    grep -q '^have_dmcrypted=' "${DSK_TEMP}" && echo "*  => is a dm-crypt device"
    grep -q '^resilvering=' "${DSK_TEMP}" && echo "rs  => Resilvering"
    grep -q '^replacing=' "${DSK_TEMP}" && echo "rpl => Replacing"
    grep -q '^offline_type=O' "${DSK_TEMP}" && echo "O  => Offline"
    grep -q '^offline_type=U' "${DSK_TEMP}" && echo "U  => Unavail"
    grep -q '^offline_type=F' "${DSK_TEMP}" && echo "F  => Faulted"
    grep -q '^offline_type=R' "${DSK_TEMP}" && echo "R  => Removed"
fi

[ -f "$ZFS_TEMP" ] && rm -f "$ZFS_TEMP"
[ -f "$LVM_TEMP" ] && rm -f "$LVM_TEMP"
[ -f "$DSK_TEMP" ] && rm -f "$DSK_TEMP"
rm -f $TEMP_FILE $PCI_DEVS
