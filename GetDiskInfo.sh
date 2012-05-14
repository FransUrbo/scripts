#!/bin/bash

#ll /sys/bus/pci/devices/0000:0[2-4]:00.0/host*/target*/[0-9]*/block*

DO_ZFS=0
if type zpool > /dev/null 2>&1; then
    DO_ZFS=1
    ZFS_TEMP=`tempfile -d /tmp -p zfs.`
    zpool status > $ZFS_TEMP 2> /dev/null
fi

printf "  %-8s %-4s %-30s%-40s%-10s%-10s%-10s%-10s\n\n" "Host" "Name" "Model" "Device by ID" "Rev" "MD" "VG" "ZFS"

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
	find /sys/bus/pci/devices/$id/{host*,ide*,cciss*} -maxdepth 0 2> /dev/null | \
	    while read path; do
	    host=`echo "$path" | sed -e 's@.*/host\(.*\)@\1@' -e 's@.*/ide\(.*\)@\1@' -e 's@.*/cciss\(.*\)@\1@'`
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
		blocks=`find $path/[0-9]*/block* 2> /dev/null`
                if [ -z "$blocks" ]; then
		    # Check again, below target* (for SCSI/SATA devices)
                    blocks=`find $path/target*/[0-9]*/block* 2> /dev/null`
                fi

                # ----------------------
                if [ -n "$blocks" ]; then
                    find $blocks | \
                        while read block; do
			    # Reset path variable to actual/full path for this device
			    path=`echo "$block" | sed 's@/block.*@@'`

                            # ----------------------
                            # Get name, model and revision
                            name=`find $path/block* | sed "s@.*:@@"`
                            model=`cat "$path/model"`
                            
                            if [ -f "$path/rev" ]; then
                                rev="`cat \"$path/rev\"`"
                            else
                                rev="n/a"
                            fi
                            
                            # ----------------------
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
                            
                            # ----------------------
			    # Get device name (Disk by ID)
			    DID=`/bin/ls -l /dev/disk/by-id/$type* | grep -v part | grep $name | sed "s@.*/$type-\(.*\) -.*@\1@"`
			    [ -z "$DID" ] && DID=n/a

                            # ----------------------
			    # Get ZFS pool data for this disk ID
			    if [ -n "$DO_ZFS" ]; then
				zfs=$(cat $ZFS_TEMP | 
				    while read zpool; do
					if echo "$zpool" | grep -q 'pool: '; then
					    zfs_name=`echo "$zpool" | sed 's@.*: @@'`
					elif echo "$zpool" | grep -q 'state: '; then
					    zfs_state=`echo "$zpool" | sed 's@.*: @@'`
					    shift ; shift ; shift ; shift ; shift
					elif echo "$zpool" | egrep -q '^raid|^mirror|^cache|^spare'; then
					    zfs_vdev=`echo "$zpool" | sed 's@ .*@@'`
					elif echo "$zpool" | egrep -q "$DID|$name"; then
					    if ! echo "$zpool" | egrep -q "ONLINE|AVAIL"; then
						offline="!"
						if echo "$zpool" | grep -q "OFFLINE"; then
						    offline="$offline"OFFLINE
						elif echo "$zpool" | grep -q "UNAVAIL"; then
						    offline="$offline"UNAVAIL
						elif echo "$zpool" | grep -q "FAULTED"; then
						    offline="$offline"FAULTED
						fi
					    fi

					    if [ "x$zfs_name" != "x" -a "x$zfs_vdev" != "x" ]; then
						printf "%-17s$offline" "$zfs_name / $zfs_vdev"
					    fi
					fi
				    done)
			    fi
			    [ -z "$zfs" ] && zfs=n/a

                            # ----------------------
                            # Get Virtual Group
                            if [ -n "$md" ]; then
                                VG=`pvscan | grep $md`
                                if [ -n "$VG" ]; then
                                    # PV /dev/md4   VG movies   lvm2 [1,36 TB / 0    free]
                                    vg=`echo "$VG" | sed -e 's@.*VG @@' -e 's@ .*@@'`
                                else
                                    vg="n/a"
                                fi
                                
                                md="$md"`echo "$dev" | sed "s@.*[0-9]\[\([0-9]\)\]@/\1@"`
                            else
                                md="n/a"
                                vg="n/a"
                            fi
                            
                            # ----------------------
                            # Output information
			    printf "  %-8s %-4s %-30s%-40s%-10s%-10s%-10s%-10s\n" $host $name "$model" "$DID" $rev $md $vg "$zfs"
                    done
                else
                    printf "  %-8s n/a\n" $host
                fi
        done

        echo
    done

[ -n "$ZFS_TEMP" ] && rm -f $ZFS_TEMP
