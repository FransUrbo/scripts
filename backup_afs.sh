#!/bin/sh

# $Id: backup_afs.sh,v 1.8 2002-10-08 06:01:40 turbo Exp $

cd /

# --------------
# Set some default variables
AFSSERVER="papadoc.bayour.com"
AFSCELL="bayour.com"
CURRENTDATE=`date +"%Y%m%d"`
MAXSIZE=2000000

# Don't change this, it's set with commandline options
TYPE="full"

# --------------
# FUNCTION: Find the LATEST modification date of a file
last_modified () {
    FILE=`echo $1 | sed -e 's@full-@*@' -e 's@incr-@*@'`
    set -- `/bin/ls -t $FILE* 2> /dev/null | sed 's@ .*@@'`
    FILE=$1

    if [ ! -z "$FILE" ]; then
	set -- `/bin/ls -l --full-time $FILE`
	shift ; shift ; shift ; shift ; shift
	mon=`echo $2 | sed -e 's@Jan@01@' -e 's@Feb@02@' -e 's@Mar@03@' -e 's@Apr@04@' \
	    -e 's@May@05@' -e 's@Jun@06@' -e 's@Jul@07@' -e 's@Aug@08@' -e 's@Sep@09@' \
	    -e 's@Oct@10@' -e 's@Nov@11@' -e 's@Dec@12@'`
	DATE="$mon/$3/$5"
    else
	DATE=""
    fi
}

# --------------
# FUNCTION: Find the mountpoint of the volume
get_vol_mnt () {
    local vol="`echo $1 | sed 's@.*\.@@'`"
    local VOL

    MNTPOINT=`find /afs/$AFSCELL/ -type d -name '[a-zA-Z0-9]*' -exec find {} -type d -name "$vol" \;`
    if [ -z "$MNTPOINT" ]; then
	# Bummer! Not found the 'easy' way, guess... (!!!)
	MNTPOINT="/afs/$AFSCELL/`echo $1 | sed 's@\.@/@g'`"
    else
	# Double check that the mountpoint really IS the volume we're checking!
	VOL=`fs examine $MNTPOINT | head -n1 | sed 's@.* @@'`
	if [ ! "$VOL" = "$1" ]; then
	    echo "Mountpoint and volume don't match. -> '$VOL != $1' ($MNTPOINT)" > /dev/stderr
	    exit 1
	fi
    fi
}

# --------------
# FUNCTION: Find the partition the volume is on
get_vol_part () {
    PART=`vos examine $1 -localauth | sed 1d | head -n1 | sed 's@.*/@/@'`
    [ ! -z "$action" -o ! -z "$verbose" ] && printf "%-65s" "Partition for volume $volume is $PART"
}

# --------------
# FUNCTION: Get the size of the volume
get_vol_size () {
    SIZE=""
    set -- `vos examine $1 -localauth | head -n1`
    SIZE=$4
}

# --------------
# FUNCTION: Create and mount the backup volume
create_backup_volume () {
    local vol="$1"
    local dir="$2"

    [ -z "$dir" ] && dir="/afs/$AFSCELL"

    if [ "$dir" == "/afs/$AFSCELL" ]; then
	OLDFILES="/afs/$AFSCELL/OldFiles_`echo $vol`-`echo $CURRENTDATE`"
    else
	OLDFILES="$dir/OldFiles_$CURRENTDATE"
    fi

    # 'Mount' the volume in the users homedirectory
    if [ -d "$OLDFILES" ]; then
	# Todays OldFiles also exists, remove the mount
	$action fs rmmount "$OLDFILES"
    fi

    $action fs mkmount "$OLDFILES" $vol.backup
}

# --------------
dump_volume () {
    local $vol="$1".backup
    local $file="$2"

    if [ $SIZE -ge $MAXSIZE ]; then
	# If the volume is bigger than 2Gb, dump in section using 'split'.

	if [ ! -z "$action" ]; then
	    RES=`$action vos dump -id $vol -server ${AFSSERVER:-localhost} \
		-partition $PART $TIMEARG -localauth 2> /dev/null \| split -b1024m - $file. 2>&1`
	else
	    RES=`vos dump -id $vol -server ${AFSSERVER:-localhost} \
		-partition $PART $TIMEARG -localauth 2> /dev/null | split -b1024m - $file. 2>&1`
	fi
    else
	RES=`$action vos dump -id $vol -server ${AFSSERVER:-localhost} \
	    -partition $PART $TIMEARG -file $file -localauth 2>&1`
    fi
}

# --------------
do_backup () {
    local VOLUMES="$*"
    local volume
    local BACKUPFILE
    local TIMEARG
    local ERROR

    [ ! -z "$verbose" ] && echo "Backing up volume:"
    for volume in $VOLUMES; do
	if [ ! -z "$action" ]; then
	    printf "%s\n" $volume
	else
	    [ ! -z "$verbose" ] && printf "  %-25s" $volume
	fi

	# Find the 'mountpoint' of the volume
	[ "$MOUNT" -gt 0 ] && get_vol_mnt $volume

	# Create the backup volume
	if [ -z "$action" ]; then
	    if [ "$BACKUP_VOLUMES" -gt 0 ]; then
		RES=`vos backup $volume -localauth 2>&1`
	    else
		$action vos backup $volume -localauth
		RES="Created backup volume for $volume"
	    fi
	else
	    $action vos backup $volume -localauth
	    RES="Created backup volume for $volume"
	fi

	# Mount the backup volume
	if ! echo $RES | grep -q 'Created backup volume for'; then
	    echo -n "Could not create backup volume for '$volume' - "

	    if echo $RES | grep -q 'VOLSER: volume is busy'; then
		echo "volume is busy."

		# Try to backup this volume later...
		MISSING_VOLUMES="$MISSING_VOLUMES $volume"
	    elif echo $RES | grep -q 'VLDB: no such entry'; then
		echo "no such volume."
	    elif echo $RES | grep -q 'VLDB: no permission access for call'; then
		echo "permission denied."
	    else
		echo "'$RES'"

		# Try to backup this volume later...
		MISSING_VOLUMES="$MISSING_VOLUMES $volume"
	    fi

	    continue
	fi

	# Mount the volume on it's mountpoint (VOLUME/OldFiles).
	[ "$MOUNT" -gt 0 ] && create_backup_volume $volume $MNTPOINT

	if [ -z "$ERROR" ]; then
	    # Find the partition the volume is on
	    get_vol_part $volume

	    # Find the size of the volume
	    get_vol_size $volume

	    # Is this a incremental or a full backup? If it's incremental, dump from
	    # last known date
	    BACKUPFILE="$BACKUPDIR/$TYPE-$volume-$CURRENTDATE"
	    if [ "$TYPE" = "incr" ]; then
		last_modified "$BACKUPDIR/$TYPE-$volume-"

		if [ ! -z "$DATE" ]; then
		    if [ ! -z "$verbose" ]; then
			echo "dump > '$DATE'"
		    fi
		    TIMEARG="-time $DATE"
		else
		    BACKUPFILE="$BACKUPDIR/full-$volume-$CURRENTDATE"
		fi
	    fi
	
	    dump_volume $volume $BACKUPFILE
	    if [ -z "$?" ]; then
		ERROR=2
	    fi

	    if echo $RES | grep -q 'Dumped volume'; then
		RES=`echo $RES | sed 's@.* /@/@'`
		[ ! -z "$verbose" ] && echo "$RES"
	    elif echo $RES | grep -q 'VLDB: vldb entry is already locked'; then
		vos unlock $volume -localauth > /dev/null 2>&1
		dump_volume $volume $BACKUPFILE
	    fi

	    # ------------------
	    # Restore the backup. It does not matter if the volume exists and is mounted,
	    # it will be removed and then created when using '-overwrite full'...
	    # 	vos restore papadoc /vicepb $volume -file full-$BACKUPFILE -overwrite full
	    # 	vos restore papadoc /vicepb $volume -file incr-$BACKUPFILE -overwrite incremental
	    #
	    # If the volume didn't exist and wasn't mounted:
	    # 	fs mkmount /afs/$AFSCELL/$MOUNTPOINT $volume
	    # 	vos release root.cell
	    # ------------------

	    if [ -z "$ERROR" ]; then
		# Remove the mountpoint
		[ "$MOUNT" -gt 0 ] && $action fs rmmount "$OLDFILES"
	    
		# Remove the backup volume
		if [ -z "$action" ]; then
		    if [ "$BACKUP_VOLUMES" -gt 0 ]; then
			vos remove -id $volume.backup -localauth > /dev/null 2>&1 &
		    else
			$action vos remove -id $volume.backup -localauth
		    fi
		else
		    $action vos remove -id $volume.backup -localauth
		fi
	    fi
	else
	    # We could not create the backup volume!
	    echo "  ERROR: $RES"
	fi

	[ ! -z "$action" -o ! -z "$verbose" ] && echo '-----'
    done
}

# =================================================================

# Don't change this
MOUNT=0 ; BACKUP_VOLUMES=1

# --------------
# Do we backup odd or even weeks?
ODD=`expr \`date +"%V"\` % 2`
if [ "$ODD" != "1" ]; then
    BACKUPDIR="/var/.backups-volumes/odd"
else
    BACKUPDIR="/var/.backups-volumes/even"
fi

# --------------
# Get the CLI options...
TEMP=`getopt -o heuimcv --long help,echo,users,incr,mount,nocreate-vol,verbose -- "$@"`
eval set -- "$TEMP"
while true ; do
    case "$1" in
	-h|--help)
	    echo "Usage:   `basename $0` [option] [volume]"
	    echo "Options: -h,--help		Show this help"
	    echo "	 -e,--echo		Don't do anything, just echo the commands"
	    echo "	 -u,--users		Backup only the user.* volumes"
	    echo "	 -i,--incr		Do a incremental backup"
	    echo "	 -m,--mount		Mount the volumes before doing the backup"
	    echo "	 -c,--nocreate-vol	Don't create the backup volume(s) before backup"
	    echo "	 -v,--verbose		Explain what's to be done"
	    echo "If volume is given, only backup that/those volumes."
	    echo 
	    exit 0
	    ;;
	-c|--nocreate-vol)	BACKUP_VOLUMES=0 ; shift ;;
	-e|--echo)		action='echo' ; shift ;;
	-u|--users)		VOLUMES=users ; shift ;;
	-i|--incr)		TYPE=incr     ; shift ;;
	-m|--mount)		MOUNT=1       ; shift ;;
	-v|--verbose)		verbose=1     ; shift ;;
	--)			shift ; VOLUMES="$*" ; break ;; 
	*)			echo "Internal error!" ; exit 1 ;;
    esac
done

# --------------
# 'Initialize' AFS access...
if ! tokens | grep -q ^User; then
    ID=`id -u`
    if [ "$ID" != "0" ]; then
	echo "You must have a valid AFS token to do a backup (or be root)." > /dev/stderr
	exit 1
    fi
fi

# --------------
# Get volumes for backup
if [ "$VOLUMES" = "users" ]; then
    VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet -localauth | grep ^user | egrep -v '^root|readonly|\.backup|\.rescue' | sed 's@\ .*@@'`
else
    if [ -z "$VOLUMES" ]; then
	VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet -localauth | egrep -v '^root|readonly|\.backup' | sed 's@\ .*@@'`
    fi
fi
VOLUMES=`echo $VOLUMES`

do_backup $VOLUMES

if [ ! -z "$MISSING_VOLUMES" ]; then
    echo "ERROR: Did not backup the volumes: $MISSING_VOLUMES." > /dev/stderr

    # Sleep for five minutes before trying again...
    echo -n "Sleeping for 5 minutes, before we try again... " > /dev/stderr
    sleep 300s

    # Backup the missing volumes...
    do_backup $MISSING_VOLUMES
else
    echo "All volumes did backup safely."
    exit 0
fi
