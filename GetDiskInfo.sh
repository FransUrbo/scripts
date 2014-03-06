#!/bin/bash

# Script to do a full inventory of all disks in the system.
# Copyleft: Turbo Fredriksson <turbo@bayour.com>
# Released under the GPL (version of your choosing).

# The following commands improve output, but is not required:
#   zpool, pvs, cryptsetup, bc
# 
# The following command is not required, but they should really
# exist for best usage:
#   lsscsi, fdisk
# 
# The following command is required (won't work without it!):
#   lspci, tempfile, getopt, basename, grep, find, cat, ls,
#   mount, readlink
#
# Extra information is stored in the following files (script will
# ignore any line that starts with a dash - #):
#   $HOME/.disks_physical_location
#       Columns: Model, Serial, Enclosure, Slot - separated by tabs
#       Example:
#
#       # Model		Serial			Enclosure	Slot
#       ST31500341AS	9VS4XK4T		4		1
#       ST31500341AS	9VS3SAWS		4		3
#
#   $HOME/.disks_serial+warranty
#       Columns: Model, Serial, Rev, Warranty, Device - separated by tabs.
#       # Model		Serial			Rev	Warranty	Device
#       ST31500341AS	9VS4XK4T		CC1H	20140112	sdf
#       ST31500341AS	9VS3SAWS		CC1H	+		sdh
#
#   For me, a '+' means that the warranty have expired. This can be any
#   character, just remember what means what. Only Model and Warranty
#   column is of importance. Must be first and fourth though!

[ "$USER" != "root" ] && \
    echo "WARNING: This script really needs to run with root privilegues." \
    > /dev/stderr

# --------------
# Set/figure out default output information
DO_ZFS=0
if type zpool > /dev/null 2>&1; then
    DO_ZFS=1
    ZFS_TEMP=`tempfile -d /tmp -p zfs.`

    if [ `zpool status 2>&1 | egrep -v '^no pools' | tee $ZFS_TEMP | wc -l` -lt 1 ]; then
	rm $ZFS_TEMP
	DO_ZFS=0
    fi
fi

DO_LVM=0
if type pvs > /dev/null 2>&1; then
    DO_LVM=1
    LVM_TEMP=`tempfile -d /tmp -p lvm.`

    if [ `pvs --noheadings --nosuffix --separator , | tee $LVM_TEMP | wc -l` -lt 1 ]; then
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

	    name=`basename "$dev_path"`
	    dev=`cryptsetup status $name | grep device: | sed 's@.*/@@'`

	    if [ -n "$name" -a -n "$dev" ]; then
		DMCRYPT="$DMCRYPT $name:$dev"
	    fi
	done
    else
	DO_DMCRYPT=0
    fi
fi

DO_LOCATION=0
if [ -f $HOME/.disks_physical_location ]; then
    DO_LOCATION=1
fi

DO_WARRANTY=0
if [ -f $HOME/.disks_serial+warranty ]; then
    DO_WARRANTY=1
fi

TEMP_FILE=`tempfile -d /tmp -p dsk.`
DO_REV=1 ; DO_MACHINE_READABLE=0

# --------------
# Get the CLI options - override DO_* above...
TEMP=`getopt -o h --long no-zfs,no-lvm,no-md,no-dmcrypt,no-location,no-warranty,no-rev,help,machine-readable -- "$@"`
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
	--machine-readable)	DO_MACHINE_READABLE=1	; shift ;;
	--help|-h)
	    echo "Usage: `basename $0` [--no-zfs|--no-lvm|--no-md|--no-dmcrypt|--no-location|--no-warranty|--no-rev|--machine-readable]"
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
    echo -n "Name;Model;Device by ID;"
    [ "$DO_REV" == 1 ] && echo -n "Rev;"
    echo -n "Serial;"
    [ "$DO_WARRANTY" == 1 ] && echo -n "Warranty;"
    [ "$DO_MD" == 1 ] && echo -n "MD;"
    [ "$DO_LVM" == 1 ] && echo -n "VG;"
    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]  && echo -n "DM-CRYPT;"
    [ "$DO_ZFS" == 1 ] && echo -n "ZFS;"
    echo "Size"
else
    printf "  %-15s" "Host" 
    [ "$DO_LOCATION" == 1 ] && printf "%-4s" "PHY"
    printf " %-4s %-20s%-45s" "Name" "Model" "Device by ID"
    [ "$DO_REV" == 1 ] && printf "%-10s" "Rev"
    printf "%-25s" "Serial"
    [ "$DO_WARRANTY" == 1 ] && printf "%-10s" "Warranty"
    [ "$DO_MD" == 1 ] && printf "%-10s" "MD"
    [ "$DO_LVM" == 1 ] && printf "%-25s" "VG"
    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]  && printf "%-25s" "DM-CRYPT"
    [ "$DO_ZFS" == 1 ] && printf "%-30s" "  ZFS"
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
# MAIN function - get a list of all PCI devices, extract storage devices.
lspci -D | \
    grep -E 'SATA|SCSI|IDE|RAID' | \
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
	find /sys/bus/pci/devices/$ctrl_id/{host*,ide*,ata*,cciss*} -maxdepth 0 2> /dev/null | \
	    while read path; do
		host=${path/*host/}
		host=${host/*ide/}
		host=${host/*ata/}
		host=${host/*cciss/}
		printf "host%0.2d;$path\n" "$host"
	    done | \
	    sort | \
		while read path; do
		    path=${path/*;/}
		    got_hosts= ; chk_ata=

		    # ----------------------
		    # Get HOST name
		    if [ -d $path/host* ]; then
			host=`echo $path/host* | sed 's@.*/@@'`
		    else
			host=${path/*\//}
		    fi

		    # ----------------------
		    # Make sure this host actually have devices attached.
		    got_hosts=`find "$path/.." -maxdepth 1 -type d -name 'host*'`
		    [[ $host =~ ^ata ]] && chk_ata=${BASH_REMATCH}
		    [ -n "$got_hosts" -a -n "$chk_ata" ] && continue

		    # ----------------------
		    # Get block path
		    blocks=`find $path -name rev 2> /dev/null | sort`

		    # ----------------------
		    if [ -n "$blocks" ]; then
			echo "$blocks" |
			    while read block; do
				# Reset path variable to actual/full path for this device
				l=$(readlink -f "$block")
				path=${l/\/rev*/}
				t_id=`basename "$path"`

				if [[ $path =~ /port-*:? ]]; then
				    # path: '/sys/devices/pci0000:00/0000:00:0b.0/0000:03:00.0/host0/port-0:0/end_device-0:0/target0:0:0/0:0:0:0'
				    host=`echo "$path" | sed "s@.*/.*\(host[0-9]\+\)/.*port-\([0-9]\+\):\([0-9]\+\)/end.*@\1:\3@"`
				fi

				# ----------------------
				# Get name
				name=
				if [[ $t_id =~ ^[0-9] ]] && type lsscsi > /dev/null 2>&1; then
				    lsscsi_out=`lsscsi --device "$t_id"`
				    if ! echo "$lsscsi_out" | grep -Eqi 'disk|dvd|cd|tape'; then
					continue
				    fi

				    name=`echo "$lsscsi_out" | sed -e 's@.*/@@' -e 's@ \[.*@@' -e 's@\[.*@@'`
				fi
				if [ -z "$name" -o "$name" == "-" ]; then
				    # /sys/block/*/device | grep '/0000:05:00.0/host8/'
				    name=`ls -ln /sys/block/*/device | \
					grep "/$t_id" | sed -e "s@.*block/\(.*\)/device .*@\1@"`
				    if [ -z "$name" ]; then
					name="n/a"
				    fi
				fi

				# ----------------------
				# Get all info availible for $name
				if [ -n "$name" -a "$name" != "n/a" ]; then
				    udevadm info -q all -p /sys/block/$name > $TEMP_FILE
				fi

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
				serial=$(get_udev_info ID_SERIAL_SHORT)

				# ----------------------
				# Get device name (Disk by ID)
				device_id=$(get_udev_info ID_SCSI_COMPAT)
				[ "$device_id" == 'n/a' ] && device_id=$(get_udev_info ID_ATA_COMPAT)

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
				    MD=`grep $name /proc/mdstat | sed 's@: active raid1 @@'`
				    if [ -n "$MD" ]; then
					# md3 sdg1[0] sdb1[1]
					set -- `echo "$MD"`
					for dev in $*; do
					    dev=${dev//\[?\]/}
					    if [[ $dev =~ ^$name(.*) ]]; then
						md=$1${BASH_REMATCH[1]}
					    elif [[ $dev =~ ^$name ]]; then
						md="$1"
						break
					    fi
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
						dev=/`cryptsetup status $dm | grep device: | sed -e 's@.*/@@' -e 's@[0-9]$@@'`
					    fi
					    if [[ $pvs =~ $lvm_regexp || $dev =~ $lvm_regexp ]]; then
						echo "$pvs" | sed "s@.*,\(.*\),lvm.*@\1@"
					    fi
					done)
				    if [ -z "$vg" -a "$md" != "n/a" ]; then
					# Double check - is it mounted
					vg=`mount | grep "/$md" | sed "s@.* on \(.*\) type.*@\1@"`
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
				    # Make sure we only match the whole word (not 'test2' if searching for/with 'test').
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
					    elif [[ $zpool =~ $vdev_regexp ]]; then
						zpool=${zpool#"${zpool%%[![:space:]]*}"} # Strip leading spaces
						zfs_vdev=${zpool/ */}
						# Somewhat ugly - this matches VDEVs that is a DEV
						if [[ ! $zfs_vdev =~ raid|mirror|cache|spare
							&& $zpool =~ $zfs_regexp
							&& -n "$zfs_name"
							&& -n "$zfs_vdev" ]]
						then
						    printf "$crypted %-17s$stat" "$zfs_name / $zfs_vdev"
						    break
						fi
					    elif [[ $zpool =~ replacing ]]; then
						replacing="rpl"`echo "$zpool" | sed "s@.*-\([0-9]\+\) .*@\1@"`
						ii=1
						continue

					    # DEV
					    elif [[ $zpool =~ $zfs_regexp ]]; then
						# Device status
						if [[ ! $zpool =~ ONLINE|AVAIL ]]; then
						    offline="!"
						    if [[ $zpool =~ OFFLINE ]]; then
							offline="$offline"O
							offline_type=O
						    elif [[ $zpool =~ UNAVAIL ]]; then
							offline="$offline"U
							offline_type=U
						    elif [[ $zpool =~ FAULTED ]]; then
							offline="$offline"F
							offline_type=F
						    elif [[ $zpool =~ REMOVED ]]; then
							offline="$offline"R
							offline_type=R
						    fi
						elif [[ $zpool =~ resilvering ]]; then
						    offline="$offline"rs
						    resilvering=1
						fi

						if [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]; then
						    if [[ -n "$tmpdmname" && $zpool =~ $tmpdmname ]]; then
							crypted="*"
							have_dmcrypted=1
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
				# Get size of disk
				if type fdisk > /dev/null 2>&1; then
				    if [ -n "$dev_path" ]; then
					size=`fdisk -l $dev_path 2> /dev/null | \
					    grep '^Disk /' | \
					    sed -e "s@.*: \(.*\), .*@\1@" \
					    -e 's@\.[0-9] @@' -e 's@ @@g'`
					if [[ $size =~ ^[0-9][0-9][0-9][0-9]GB ]] && type bc > /dev/null 2>&1; then
					    s=${size/GB/}
					    size=`echo "scale=2; $s / 1024" | bc`"TB"
					elif [[ $size =~ ^[0-9][0-9][0-9][0-9]MB ]] && type bc > /dev/null 2>&1; then
					    s=${size/MB/}
					    size=`echo "scale=2; $s / 1024" | bc`"GB"
					fi
				    fi
				fi
				if [ -z "$size" ]; then
				    size="n/a"
				fi

				# ----------------------
				# Get warranty information
				if [ "$DO_WARRANTY" == 1 ]; then
				    if [[ $model =~ " " ]]; then
					tmpmodel=${model// /}
				    else
					tmpmodel="$model"
				    fi

				    set -- `grep -E -w "^$tmpmodel.*$serial" ~/.disks_serial+warranty`
				    if [ -n "$4" ]; then
					warranty="$4"
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

				    set -- `grep -E -w "^$tmpmodel.*$serial" ~/.disks_physical_location`
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
				    echo -n "$name;$model;$device_id;"
				    [ "$DO_REV" == 1 ] && echo -n "$rev;"
				    echo -n "$serial;"
				    [ "$DO_WARRANTY" == 1 ] && echo -n "$warranty;"
				    [ "$DO_MD" == 1 ] && echo -n "$md;"
				    [ "$DO_LVM" == 1 ] && echo -n "$vg;"
				    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ] && echo -n "$dmcrypt;"
				    [ "$DO_ZFS" == 1 ] && echo -n "$zfs;"
				    echo "$size"
				else
				    printf "  %-15s" "$host"
				    [ "$DO_LOCATION" == 1 ] && printf "%-4s" "$location"
				    printf " %-4s %-20s%-45s" "$name" "$model" "$device_id"
				    [ "$DO_REV" == 1 ] && printf "%-10s" "$rev"
				    printf "%-25s" "$serial"
				    [ "$DO_WARRANTY" == 1 ] && printf "%-10s" "$warranty"
				    [ "$DO_MD" == 1 ] && printf "%-10s" "$md"
				    [ "$DO_LVM" == 1 ] && printf "%-25s" "$vg"
				    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ] && printf "%-25s" "$dmcrypt"
				    [ "$DO_ZFS" == 1 ] && printf "%-30s" "$zfs"
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
    [ -n "$have_dmcrypted" ] && echo "*  => is a dm-crypt device"
    [ -n "$resilvering" ] && echo "rs => Resilvering"
    [ "$offline_type" == "O" ] && echo "O  => Offline"
    [ "$offline_type" == "U" ] && echo "U  => Unavail"
    [ "$offline_type" == "F" ] && echo "F  => Faulted"
    [ "$offline_type" == "R" ] && echo "R  => Removed"
fi

[ -f "$ZFS_TEMP" ] && rm -f "$ZFS_TEMP"
[ -f "$LVM_TEMP" ] && rm -f "$LVM_TEMP"
rm -f $TEMP_FILE
