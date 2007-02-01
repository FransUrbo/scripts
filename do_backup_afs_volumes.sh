#!/bin/sh

BACKUPVOLDIR=/var/.backups/Volumes
for dir in odd even; do
    [ ! -d $BACKUPVOLDIR/$dir ] && mkdir -p $BACKUPVOLDIR/$dir
done

echo "CMD: 'do_backup_afs_volumes.sh $*'"

# Backup the AFS volumes
if [ -x /usr/local/sbin/backup_afs.sh ]; then
    echo "Starting AFS volume backup at" `date +"%Y%m%d %H:%M:%S"`

    ODD=`expr \`date +"%V"\` % 2`
    DAY=`date +"%w"`

    # Do we backup odd or even weeks?
    if [ "$DAY" = "1" -o "$BACKUP_TYPE" == "full" -o "$1" == "Full" ]; then
	# This is a monday (or we've specified full backup), clean
	# the backup directory. We'll have PREVIOUS weeks backup(s)
	# intact -> At least one weeks of backup(s) online.

# Unfortunatly I don't have enough space on my backup partition
# to save two full weeks, therefor I'm deleting ALL backups, and
# start over. HOPFULLY it's saved to tape by now...
#
# If you HAVE enough room for two full weeks, uncomment the if/else/fi
# lines below.
#	if [ "$ODD" != "1" ]; then
	    # Odd weeks
	    for file in $BACKUPVOLDIR/odd/*; do
		: > $file
		rm -rf $file
	    done
#	else
	    # Even weeks
	    for file in $BACKUPVOLDIR/even/*; do
		: > $file
		rm -rf $file
	    done
#	fi

	# Do a FULL backup
	/usr/local/sbin/backup_afs.sh --nodelete-vol 2>&1
    elif [ "$BACKUP_TYPE" == "diffr" -o "$1" == "Differential" ]; then
	# Do a DIFFERENTIAL backup
	/etc/bacula/scripts/backup_afs.sh --diffr --nodelete-vol 2>&1
    else
	# Do a INCREMENTAL volume backup
	/usr/local/sbin/backup_afs.sh -i --nodelete-vol 2>&1
    fi

    echo "Ending AFS volume backup at" `date +"%Y%m%d %H:%M:%S"`
fi
