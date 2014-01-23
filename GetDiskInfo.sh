#!/bin/bash

#ll /sys/bus/pci/devices/0000:0[2-4]:00.0/host*/target*/[0-9]*/block*

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
        --help)
	    echo "Usage: `basename $0` [--no-zfs|--no-pvm|--no-md|--no-dmcrypt|--no-location|--no-warranty|--no-rev|--machine-readable]"
            echo
            exit 0
            ;;
	--)		shift ; break ;;
	*)		echo "Internal error!"	; exit 1 ;;
    esac
done

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

lspci -D | \
    egrep 'SATA|SCSI|IDE|RAID' | \
    while read line; do
	id=`echo "$line" | sed 's@ .*@@'`

	if echo $line | egrep -q 'SATA|SCSI|RAID'; then
	    type=scsi
	else
	    type=ata
	fi

        if [ "$DO_MACHINE_READABLE" == 1 ]; then
            ctrl="$line"
        else
            echo "$line"
        fi

	# First while, just to sort '.../host2' before '.../host10'.
	find /sys/bus/pci/devices/$id/{host*,ide*,ata*,cciss*} -maxdepth 0 2> /dev/null | \
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

		    got_hosts=`find "$path/.." -maxdepth 1 -type d -name 'host*'`
		    chk_ata=`echo "$host" | grep ^ata`
		    [ -n "$got_hosts" -a -n "$chk_ata" ] && continue

		    # ----------------------
		    # Get block path
		    blocks=`find $path/[0-9]*/block*/* -maxdepth 0 2> /dev/null`
		    if [ -z "$blocks" ]; then
			# Check again - look for the 'rev' file. 
			blocks=`find $path/target*/[0-9]*/rev 2> /dev/null`
			if [ -n "$blocks" ]; then
			    blocks=`find $path/target*/[0-9]* -maxdepth 0 | head -n1`
			else
                            # Third check - catch the SAS2LP
                            ports=`find $path -maxdepth 2 -name 'port-*:?' -type d | head -n1`
                            if [ -n "$ports" ]; then
                                blocks=`echo "$ports" | sed 's@/end_dev.*@@'`
                            else
				# Fouth check - catch cciss targets.
                                blocks=`find $path -name rev 2> /dev/null`
                                if [ -n "$blocks" ]; then
                                    blocks=`dirname "$blocks"`
                                fi
                            fi
                        fi
                    fi

		    # ----------------------
		    if [ -n "$blocks" ]; then
			find $blocks/../.. -name 'rev' |
			    while read block; do
				# Reset path variable to actual/full path for this device
				path=`echo "$block" | sed 's@/rev.*@@'`
				pushd $path > /dev/null 2>&1
				path=`/bin/pwd`
				popd > /dev/null 2>&1
				t_id=`basename "$path"`

				if echo "$path" | egrep -q '/port-*:?'; then
                                    # path: '/sys/devices/pci0000:00/0000:00:0b.0/0000:03:00.0/host0/port-0:0/end_device-0:0/target0:0:0/0:0:0:0'
                                    host=`echo "$path" | sed "s@.*/.*\(host[0-9]\+\)/.*port-\([0-9]\+\):\([0-9]\+\)/end.*@\1:\3@"`
                                fi

				# ----------------------
				# Get name
				name=""
				if echo "$t_id" | egrep -q "^[0-9]" && type lsscsi > /dev/null 2>&1; then
				    name=`lsscsi --device "$t_id" | sed -e 's@.*/@@' -e 's@ \[.*@@' -e 's@\[.*@@'`
				fi
				if [ -z "$name" -o "$name" == "-" ]; then
				    # /sys/block/*/device | grep '/0000:05:00.0/host8/'
				    name=`stat /sys/block/*/device | \
					egrep "File: .*/$id.*$host/.*$t_id|File: .*/$t_id" | \
					sed -e "s@.*block/\(.*\)/device'.*@\1@" \
				            -e 's@.*\!@@'`
				    if [ -z "$name" ]; then
					name="n/a"
				    fi
				fi
                                dev_path=`find /dev -name "$name" -type b`

				# ... model
				model=`cat "$path/model" | sed -e 's@-.*@@' -e 's/ *$//g'`

				# ... and revision
                                if [ "$DO_REV" == 1 ]; then
				    if [ -f "$path/rev" ]; then
				        rev="`cat \"$path/rev\"`"
				    else
				        rev="n/a"
				    fi
                                fi

                                # ... serial number
                                if [ -b "/dev/$name" ]; then
                                    if type hdparm > /dev/null 2>&1; then
                                        set -- `hdparm -I /dev/$name 2> /dev/null | \
                                            grep 'Serial Number:' | sed 's@Serial Number:@@'`
                                        serial=$1
				    fi
                                fi
                                [ -z "$serial" ] && serial="n/a"

				# ----------------------
				DID="n/a"
				if [ -n "$name" -a "$name" != "n/a" ]; then
				    # ----------------------
				    if [ "$DO_MD" == 1 ]; then
					# Get MD device
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
				    if [ -d "/dev/disk/by-id" ]; then
					# Get device name (Disk by ID)
					DID=`/bin/ls -l /dev/disk/by-id/$type* | \
					    grep -v part | \
					    grep $name | \
					    sed "s@.*/$type-\(.*\) -.*@\1@"`
                                        if [ -z "$DID" ]; then
                                            # Try again, with a partition.
                                            DID=`/bin/ls -l /dev/disk/by-id/$type* | \
						grep $name | \
						sed "s@.*/$type-\(.*\)-part.* -.*@\1@" | \
						head -n1`
                                        fi
				    fi

				    # ----------------------
				    # Get ZFS pool data for this disk ID
				    if [ "$DO_ZFS" == 1 -a -f "$ZFS_TEMP" ]; then
					# OID: SATA_Corsair_Force_311486508000008952122
					# ZFS: ata-Corsair_Force_3_SSD_11486508000008952122
					#tmpnam=`echo "$DID" | sed "s@SATA_\(.*_.*\)_[0-9].*@\1@"`
                                        tmpnam=`echo "$DID" | sed "s@SATA_@@"`

                                        # Setup a matching string.
                                        # egrep matches _every line_ if 'NULL|sda|NULL'!
                                        [ -n "$DID" ] && zfs_regexp="$DID"
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
						elif echo "$zpool" | egrep -q '^raid|^mirror|^cache|^spare'; then
						    zfs_vdev=`echo "$zpool" | sed 's@ .*@@'`
                                                elif echo "$zpool" | grep -q 'replacing'; then
                                                    replacing="rpl"`echo "$zpool" | sed "s@.*-\([0-9]\+\) .*@\1@"`
                                                    ii=1
						elif echo "$zpool" | egrep -q "$zfs_regexp"; then
						    if ! echo "$zpool" | egrep -q "ONLINE|AVAIL"; then
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
                                                        if echo "$zpool" | egrep -q "$tmpdmname"; then
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
                                                    ii=`expr $ii + 1`
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
						if echo "$pvs" | egrep -q "$lvm_regexp"; then
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
                                            echo "$DID" | grep -q "$dm_dev" && dmcrypt=$dm_name
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
						    -e 's@\.[0-9] @@'`
					    if echo "$size" | egrep -q '^[0-9][0-9][0-9][0-9]GB' && type bc > /dev/null 2>&1; then
						s=`echo "$size" | sed 's@GB@@'`
						size=`echo "scale=2; $s / 1024" | bc`"TB"
					    fi
					fi
				    fi
				    if [ -z "$size" ]; then
                                        size="n/a"
                                    else
                                        size=`echo "$size" | sed 's@ @@g'`
                                    fi
				fi

				# ----------------------
                                # Get warranty information
                                # Columns: Model, Serial, Rev, Warranty, Device separated
                                # by tabs.
                                if [ "$DO_WARRANTY" == 1 ]; then
                                    if echo "$model" | grep -q " "; then
                                        tmpmodel=`echo "$model" | sed 's@ @@g'`
                                    else
                                        tmpmodel="$model"
                                    fi

                                    set -- `egrep -w "^$tmpmodel.*$serial" ~/.disks_serial+warranty`
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
                                # Columns: Model, Serial, Enclosure, Slot separated by tabs
                                if [ "$DO_LOCATION" == 1 ]; then
                                    if echo "$model" | grep -q " "; then
                                        tmpmodel=`echo "$model" | sed 's@ @@g'`
                                    else
                                        tmpmodel="$model"
                                    fi

                                    set -- `egrep -w "^$tmpmodel.*$serial" ~/.disks_physical_location`
                                    if [ -n "$3" -a -n "$4" ]; then
                                        location="$3:$4"
                                    else
                                        location="n/a"
                                    fi
                                else
                                    location="n/a"
                                fi

				# ----------------------
				# Output information
                                if [ "$DO_MACHINE_READABLE" == 1 ]; then
                                    echo -n "$ctrl;$host;"
                                    [ "$DO_LOCATION" == 1 ] && echo -n "$location;"
                                    echo -n "$name;$model;$DID;"
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
                                    printf " %-4s %-20s%-45s" "$name" "$model" "$DID"
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
