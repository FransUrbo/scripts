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

printf "  %-9s %-4s %-20s%-45s%-10s%-25s" "Host" "Name" "Model" "Device by ID" "Rev" "Serial"
[ -n "$DO_MD" ] && printf "%-10s" "MD"
[ -n "$DO_PVM" -a -f "$PVM_TEMP" ] && printf "%-10s" "VG"
[ -n "$DO_DMCRYPT" -a -n "$DMCRYPT" ]  && printf "%-25s" "DM-CRYPT"
[ -n "$DO_ZFS" -a -f "$ZFS_TEMP" ] && printf "%-25s" "    ZFS"
printf "  %8s\n\n" "Size"

lspci -D | \
    egrep 'SATA|SCSI|IDE|RAID' | \
    while read line; do
	id=`echo "$line" | sed 's@ .*@@'`

	if echo $line | egrep -q 'SATA|SCSI|RAID'; then
	    type=scsi
	else
	    type=ata
	fi

        echo "$line"

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
		    # Get HOST ID
		    host=`echo "$path" | sed 's@.*/@@'`

		    # ----------------------
		    # Get block path
		    blocks=`find $path/[0-9]*/block*/* -maxdepth 0 2> /dev/null`
		    if [ -z "$blocks" ]; then
			# Check again - look for the 'rev' file. 
			blocks=`find $path/target*/[0-9]*/rev 2> /dev/null`
			if [ -n "$blocks" ]; then
			    blocks=`find $path/target*/[0-9]* -maxdepth 0`
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
                                    host=`echo "$path" | sed "s@.*/host.*/\(.*\)/end_.*@\1@"`
                                fi

				# ----------------------
				# Get name
				name=""
				if echo "$t_id" | egrep -q "^[0-9]" -a type lsscsi > /dev/null 2>&1; then
				    name=`lsscsi --device "$t_id" | sed -e 's@.*/@@' -e 's@\[.*@@'`
				fi
				if [ -z "$name" -o "$name" == "-" ]; then
				    # /sys/block/*/device | grep '/0000:05:00.0/host8/'
				    name=`stat /sys/block/*/device | \
					egrep "File: .*/$id.*$host/" | \
					tail -n1 | \
					sed -e "s@.*block/\(.*\)/device'.*@\1@" \
				            -e 's@.*\!@@'`
				    if [ -z "$name" ]; then
					name="n/a"
				    fi
				fi
                                dev_path=`find /dev -name "$name" -type b`

				# ... model
				model=`cat "$path/model"`

				# ... and revision
				if [ -f "$path/rev" ]; then
				    rev="`cat \"$path/rev\"`"
				else
				    rev="n/a"
				fi

                                # ... serial number
                                if [ -b "/dev/$name" ]; then
                                    if type hdparm > /dev/null 2>&1; then
                                        serial=`hdparm -I /dev/$name 2> /dev/null | \
					    grep 'Serial Number:' | sed 's@.* @@'`
                                    fi
                                fi
                                [ -z "$serial" ] && serial="n/a"

				# ----------------------
				DID="n/a"
				if [ -n "$name" -a "$name" != "n/a" ]; then
				    # ----------------------
				    if [ -n "$DO_MD" ]; then
					# Get MD device
					MD=`grep $name /proc/mdstat | sed 's@: active raid1 @@'`
					if [ -n "$MD" ]; then
					    # md3 sdg1[0] sdb1[1]
					    set -- `echo "$MD"`
					    for dev in $*; do
						if echo "$dev" | grep -q "^$name[0-9]"; then
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
				    if [ -n "$DO_ZFS" -a -f "$ZFS_TEMP" ]; then
					# OID: SATA_Corsair_Force_311486508000008952122
					# ZFS: ata-Corsair_Force_3_SSD_11486508000008952122
					tmpnam=`echo "$DID" | sed "s@SATA_\(.*_.*\)_[0-9].*@\1@"`

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
					if [ -n "$DO_DMCRYPT" -a -n "$DMCRYPT" ]; then
					    for dm_dev_name in $DMCRYPT; do
						if echo $dm_dev_name | grep -q ":$name"; then
						    tmpdmname=`echo "$dm_dev_name" | sed 's@:.*@@'`
						    zfs_regexp="$zfs_regexp|$tmpdmname"
						fi
					    done
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
						elif echo "$zpool" | egrep -q "$zfs_regexp"; then
						    if ! echo "$zpool" | egrep -q "ONLINE|AVAIL"; then
							offline="!"
							if echo "$zpool" | grep -q "OFFLINE"; then
							    offline="$offline"O
							elif echo "$zpool" | grep -q "UNAVAIL"; then
							    offline="$offline"U
							elif echo "$zpool" | grep -q "FAULTED"; then
							    offline="$offline"F
							elif echo "$zpool" | grep -q "REMOVED"; then
							    offline="$offline"R
							fi
                                                    elif echo "$zpool" | grep -q "resilvering"; then
                                                        offline=" "rs
						    fi

                                                    if [ -n "$DO_DMCRYPT" -a -n "$DMCRYPT" ]; then
                                                        if echo "$zpool" | egrep -q "$tmpdmname"; then
                                                            crypted="*"
                                                        fi
                                                    fi

						    if [ "x$zfs_name" != "" -a "$zfs_vdev" != "" ]; then
							printf "$crypted %-17s$offline" "$zfs_name / $zfs_vdev"
						    fi
						fi
					    done)
					[ -z "$zfs" ] && zfs="  n/a"
				    fi

				    # ----------------------
				    # Get LVM data (VG - Virtual Group) for this disk
				    lvm_regexp="/$name"
				    [ -n "$md" -a "$md" != "n/a" ] && lvm_regexp="$lvm_regexp|$md"
				    if [ -n "$DO_PVM" -a -f "$PVM_TEMP" ]; then
					vg=$(cat $PVM_TEMP |
					    while read pvs; do
						if echo "$pvs" | egrep -q "$lvm_regexp"; then
						    echo "$pvs" | sed "s@.*,\(.*\),lvm.*@\1@"
						fi
					    done)
                                        [ -z "$vg" ] && vg="n/a"
				    fi

				    # ----------------------
				    # Get DM-CRYPT device mapper name
				    if [ -n "$DO_DMCRYPT" -a -n "$DMCRYPT" ]; then
					for dm_dev_name in $DMCRYPT; do
					    set -- `echo $dm_dev_name | sed 's@:@ @'`
					    dm_name=$1 ; dm_dev=$2

					    echo "$DID" | grep -q "$dm_name" && dmcrypt=$dm_name
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
					    if echo "$size" | egrep -q '^[0-9][0-9][0-9][0-9]GB'; then
						s=`echo "$size" | sed 's@GB@@'`
						size=`echo "scale=2; $s / 1024" | bc`"TB"
					    fi
					fi
				    fi
				    [ -z "$size" ] && size="n/a"
				fi

				# ----------------------
				# Output information
				printf "  %-9s %-4s %-20s%-45s%-10s%-25s" \
                                    $host $name "$model" "$DID" $rev $serial
                                [ -n "$DO_MD" ] && printf "%-10s" "$md"
                                [ -n "$DO_PVM" -a -f "$PVM_TEMP" ] && printf "%-10s" "$vg"
                                [ -n "$DO_DMCRYPT" -a -n "$DMCRYPT" ] && printf "%-25s" "$dmcrypt"
                                [ -n "$DO_ZFS" -a -f "$ZFS_TEMP" ] && printf "  %-25s" "$zfs"
                                printf "%8s\n" "$size"
			    done # => 'while read block; do'
		    else
			printf "  %-9s n/a\n" $host
		    fi
		done # => 'while read path; do'

        echo
    done

[ -n "$DO_DMCRYPT" ] && echo "* => is a dm-crypt device"
[ -n "$ZFS_TEMP" ] && rm -f $ZFS_TEMP
[ -n "$PVM_TEMP" ] && rm -f $PVM_TEMP
