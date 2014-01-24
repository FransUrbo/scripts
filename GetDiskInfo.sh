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
DO_ZFS=
if type zpool > /dev/null 2>&1; then
    DO_ZFS=1
    ZFS_TEMP=`tempfile -d /tmp -p zfs.`
    zpool status > $ZFS_TEMP 2> /dev/null
fi

DO_PVM=
if type pvs > /dev/null 2>&1; then
    DO_PVM=1
    PVM_TEMP=`tempfile -d /tmp -p pvm.`
    pvs --noheadings --nosuffix --separator , \
        >  $PVM_TEMP \
        2> /dev/null
fi

DO_MD=
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
	    DMCRYPT="$DMCRYPT $name:$dev"
	done
    else
	DO_DMCRYPT=
    fi
fi

DO_LOCATION=
if [ -f $HOME/.disks_physical_location ]; then
    DO_LOCATION=1
fi

DO_WARRANTY=
if [ -f $HOME/.disks_serial+warranty ]; then
    DO_WARRANTY=1
fi

TEMP_FILE=`tempfile -d /tmp -p dsk.`
DO_REV=1 ; DO_MACHINE_READABLE=0

# --------------
# Get the CLI options - override DO_* above...
TEMP=`getopt -o h --long no-zfs,no-pvm,no-md,no-dmcrypt,no-location,no-warranty,no-rev,help,machine-readable -- "$@"`
eval set -- "$TEMP"
while true ; do
    case "$1" in
        --no-zfs)		DO_ZFS=0		; shift ;;
        --no-pvm)		DO_PVM=0		; shift ;;
        --no-md)		DO_MD=0			; shift ;;
        --no-dmcrypt)		DO_DMCRYPT=0		; shift ;;
        --no-location)		DO_LOCATION=0		; shift ;;
        --no-warranty)		DO_WARRANTY=0		; shift ;;
        --no-rev)		DO_REV=0		; shift ;;
        --machine-readable)	DO_MACHINE_READABLE=1	; shift ;;
        --help|-h)
	    echo "Usage: `basename $0` [--no-zfs|--no-pvm|--no-md|--no-dmcrypt|--no-location|--no-warranty|--no-rev|--machine-readable]"
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
    [ "$DO_PVM" == 1 -a -f "$PVM_TEMP" ] && echo -n "VG;"
    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]  && echo -n "DM-CRYPT;"
    [ "$DO_ZFS" == 1 -a -f "$ZFS_TEMP" ] && echo -n "ZFS;"
    echo "Size"
else
    printf "  %-15s" "Host" 
    [ "$DO_LOCATION" == 1 ] && printf "%-4s" "PHY"
    printf " %-4s %-20s%-45s" "Name" "Model" "Device by ID"
    [ "$DO_REV" == 1 ] && printf "%-10s" "Rev"
    printf "%-25s" "Serial"
    [ "$DO_WARRANTY" == 1 ] && printf "%-10s" "Warranty"
    [ "$DO_MD" == 1 ] && printf "%-10s" "MD"
    [ "$DO_PVM" == 1 -a -f "$PVM_TEMP" ] && printf "%-10s" "VG"
    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]  && printf "%-25s" "DM-CRYPT"
    [ "$DO_ZFS" == 1 -a -f "$ZFS_TEMP" ] && printf "%-30s" "  ZFS"
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
	ctrl_id=`echo "$line" | sed 's@ .*@@'`

        # --------------
        # What type is this - ata/ide or scsi/sata
	if echo $line | grep -E -q 'SATA|SCSI|RAID'; then
	    if echo $line | grep -q 'IDE mode'; then
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
	    host=`echo "$path" | sed -e 's@.*/host\(.*\)@\1@' -e 's@.*/ide\(.*\)@\1@' \
			-e 's@.*/ata\(.*\)@\1@' -e 's@.*/cciss\(.*\)@\1@'`
            printf "host%0.2d;$path\n" "$host"
	done | \
	    sort | \
		sed 's@.*;@@' | \
		while read path; do
		    # ----------------------
		    # Get HOST name
		    if [ -d $path/host* ]; then
                        host=`echo $path/host* | sed 's@.*/@@'`
                    else
		        host=`echo "$path" | sed 's@.*/@@'`
                    fi

		    # ----------------------
                    # Make sure this host actually have devices attached.
		    got_hosts=`find "$path/.." -maxdepth 1 -type d -name 'host*'`
		    chk_ata=`echo "$host" | grep ^ata`
		    [ -n "$got_hosts" -a -n "$chk_ata" ] && continue

		    # ----------------------
		    # Get block path
                    blocks=`find $path -name rev 2> /dev/null | sort`

		    # ----------------------
		    if [ -n "$blocks" ]; then
			echo "$blocks" |
			    while read block; do
				# Reset path variable to actual/full path for this device
                                path=$(readlink -f "$block" | sed 's@/rev.*@@')
				t_id=`basename "$path"`

				if echo "$path" | grep -E -q '/port-*:?'; then
                                    # path: '/sys/devices/pci0000:00/0000:00:0b.0/0000:03:00.0/host0/port-0:0/end_device-0:0/target0:0:0/0:0:0:0'
                                    host=`echo "$path" | sed "s@.*/.*\(host[0-9]\+\)/.*port-\([0-9]\+\):\([0-9]\+\)/end.*@\1:\3@"`
                                fi

				# ----------------------
				# Get name
				name=
				if echo "$t_id" | grep -E -q "^[0-9]" && type lsscsi > /dev/null 2>&1; then
				    name=`lsscsi --device "$t_id" | sed -e 's@.*/@@' -e 's@ \[.*@@' -e 's@\[.*@@'`
				fi
				if [ -z "$name" -o "$name" == "-" ]; then
				    # /sys/block/*/device | grep '/0000:05:00.0/host8/'
				    name=`ls -ln /sys/block/*/device | \
                                        grep "/$t_id" | sed -e "s@.*block/\(.*\)/device.*@\1@"`
				    if [ -z "$name" ]; then
					name="n/a"
				    fi
				fi

				# ----------------------
                                # Get all info availible for $name
                                udevadm info -q all -p /sys/block/$name > $TEMP_FILE
                                
				# ----------------------
                                # Get dev path
                                dev_path=$(get_udev_info DEVNAME)

				# ----------------------
				# Get model
				model=$(get_udev_info ID_MODEL | sed 's@-.*@@')

				# ----------------------
				# Get and revision
                                [ "$DO_REV" == 1 ] && rev=$(get_udev_info ID_REVISION)

				# ----------------------
                                # Get serial number
                                serial=$(get_udev_info ID_SERIAL_SHORT)

				# ----------------------
				# Get device name (Disk by ID)
                                device_id=$(get_udev_info ID_SCSI_COMPAT)

				# ----------------------
				# Get MD device
				if [ "$DO_MD" == 1 ]; then
				    MD=`grep $name /proc/mdstat | sed 's@: active raid1 @@'`
				    if [ -n "$MD" ]; then
					# md3 sdg1[0] sdb1[1]
					set -- `echo "$MD"`
					for dev in $*; do
					    if echo "$dev" | grep -q "^$name"; then
						md="$1"
						break
					    fi
					done
				    fi
				    [ -z "$md" ] && md="n/a"
				fi

				# ----------------------
				# Get ZFS pool data for this disk ID
				if [ "$DO_ZFS" == 1 -a -f "$ZFS_TEMP" ]; then
				    # OID: SATA_Corsair_Force_311486508000008952122
				    # ZFS: ata-Corsair_Force_3_SSD_11486508000008952122
                                    tmpnam=`echo "$device_id" | sed "s@SATA_@@"`

                                    # Setup a matching string.
                                    # grep -E matches _every line_ if 'NULL|sda|NULL'!
                                    [ -n "$device_id" ] && zfs_regexp="$device_id"
                                    if [ -n "$name" ]; then
                                        if [ -n "$zfs_regexp" ]; then
                                            zfs_regexp="$zfs_regexp|$name"
                                        else
                                            zfs_regexp="$name"
                                        fi
                                    fi
                                    if [ -n "$tmpnam" ]; then
                                        if [ -n "$zfs_regexp" ]; then
                                            zfs_regexp="$zfs_regexp|$tmpnam"
                                        else
                                            zfs_regexp="$tmpnam"
                                        fi
                                    fi
				    if [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]; then
					for dm_dev_name in $DMCRYPT; do
					    if echo $dm_dev_name | grep -q ":$name"; then
						tmpdmname=`echo "$dm_dev_name" | sed 's@:.*@@'`
						zfs_regexp="$zfs_regexp|$tmpdmname"
					    fi
					done
				    fi
                                    if [ -n "$model" -a -n "$serial" ]; then
                                        zfs_regexp="$zfs_regexp|$model-.*_$serial"
                                    fi
                                    
				    zfs=$(cat $ZFS_TEMP | 
					while read zpool; do
                                            offline="" ; crypted=" "
					    if echo "$zpool" | grep -q 'pool: '; then
						zfs_name=`echo "$zpool" | sed 's@.*: @@'`
					    elif echo "$zpool" | grep -q 'state: '; then
						zfs_state=`echo "$zpool" | sed 's@.*: @@'`
						shift ; shift ; shift ; shift ; shift
					    elif echo "$zpool" | grep -E -q '^raid|^mirror|^cache|^spare'; then
						zfs_vdev=`echo "$zpool" | sed 's@ .*@@'`
                                            elif echo "$zpool" | grep -q 'replacing'; then
                                                replacing="rpl"`echo "$zpool" | sed "s@.*-\([0-9]\+\) .*@\1@"`
                                                ii=1
					    elif echo "$zpool" | grep -E -q "$zfs_regexp"; then
						if ! echo "$zpool" | grep -E -q "ONLINE|AVAIL"; then
						    offline="!"
						    if echo "$zpool" | grep -q "OFFLINE"; then
							offline="$offline"O
                                                        offline_type=O
						    elif echo "$zpool" | grep -q "UNAVAIL"; then
							offline="$offline"U
                                                        offline_type=U
						    elif echo "$zpool" | grep -q "FAULTED"; then
							offline="$offline"F
                                                        offline_type=F
						    elif echo "$zpool" | grep -q "REMOVED"; then
							offline="$offline"R
                                                        offline_type=R
						    fi
                                                elif echo "$zpool" | grep -q "resilvering"; then
                                                    offline="$offline"rs
                                                    resilvering=1
						fi

                                                if [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]; then
                                                    if echo "$zpool" | grep -E -q "$tmpdmname"; then
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

						if [ "x$zfs_name" != "" -a "$zfs_vdev" != "" ]; then
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
				# Get LVM data (VG - Virtual Group) for this disk
				lvm_regexp="/$name"
				[ -n "$md" -a "$md" != "n/a" ] && lvm_regexp="$lvm_regexp|$md"
				if [ "$DO_PVM" == 1 -a -f "$PVM_TEMP" ]; then
				    vg=$(cat $PVM_TEMP |
					while read pvs; do
					    if echo "$pvs" | grep -E -q "$lvm_regexp"; then
						echo "$pvs" | sed "s@.*,\(.*\),lvm.*@\1@"
					    fi
					    done)
                                    if [ -z "$vg" ]; then
					    # Double check - is it mounted
					vg=`mount | grep "/$md" | sed "s@.* on \(.*\) type.*@\1@"`
				    fi					    
                                    [ -z "$vg" ] && vg="n/a"
				fi

				# ----------------------
				# Get DM-CRYPT device mapper name
				if [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ]; then
				    for dm_dev_name in $DMCRYPT; do
                                        set -- `echo $dm_dev_name | sed 's@:@ @'`
                                        dm_name=$1 ; dm_dev=`echo $2 |  sed -e 's@[0-9]@@'`
                                        echo "$device_id" | grep -q "$dm_dev" && dmcrypt=$dm_name
                                        [ "$name" == "$dm_dev" ] && dmcrypt=$dm_name
				    done
                                    [ -z "$dmcrypt" ] && dmcrypt="n/a"
				fi

				# ----------------------
				# Get size of disk
				if type fdisk > /dev/null 2>&1; then
				    if [ -n "$dev_path" ]; then
					size=`fdisk -l $dev_path 2> /dev/null | \
					    grep '^Disk /' | \
					    sed -e "s@.*: \(.*\), .*@\1@" \
					    -e 's@\.[0-9] @@' -e 's@ @@g'`
					if echo "$size" | grep -E -q '^[0-9][0-9][0-9][0-9]GB' && type bc > /dev/null 2>&1; then
					    s=`echo "$size" | sed 's@GB@@'`
					    size=`echo "scale=2; $s / 1024" | bc`"TB"
                                        elif echo "$size" | grep -E -q '^[0-9][0-9][0-9][0-9]MB' && type bc > /dev/null 2>&1; then
					    s=`echo "$size" | sed 's@MB@@'`
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
                                    if echo "$model" | grep -q " "; then
                                        tmpmodel=`echo "$model" | sed 's@ @@g'`
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
                                    if echo "$model" | grep -q " "; then
                                        tmpmodel=`echo "$model" | sed 's@ @@g'`
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
                                    [ "$DO_PVM" == 1 -a -f "$PVM_TEMP" ] && echo -n "$vg;"
                                    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ] && echo -n "$dmcrypt;"
                                    [ "$DO_ZFS" == 1 -a -f "$ZFS_TEMP" ] && echo -n "$zfs;"
                                    echo "$size"
                                else
				    printf "  %-15s" "$host"
                                    [ "$DO_LOCATION" == 1 ] && printf "%-4s" "$location"
                                    printf " %-4s %-20s%-45s" "$name" "$model" "$device_id"
                                    [ "$DO_REV" == 1 ] && printf "%-10s" "$rev"
                                    printf "%-25s" "$serial"
                                    [ "$DO_WARRANTY" == 1 ] && printf "%-10s" "$warranty"
                                    [ "$DO_MD" == 1 ] && printf "%-10s" "$md"
                                    [ "$DO_PVM" == 1 -a -f "$PVM_TEMP" ] && printf "%-10s" "$vg"
                                    [ "$DO_DMCRYPT" == 1 -a -n "$DMCRYPT" ] && printf "%-25s" "$dmcrypt"
                                    [ "$DO_ZFS" == 1 -a -f "$ZFS_TEMP" ] && printf "%-30s" "$zfs"
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

[ -n "$ZFS_TEMP" ] && rm -f $ZFS_TEMP
[ -n "$PVM_TEMP" ] && rm -f $PVM_TEMP
rm -f $TEMP_FILE
