#!/bin/sh

# $Id: salvage_afs.sh,v 1.3 2004-09-18 09:00:32 turbo Exp $

cd /

# --------------
# Set some default variables
AFSSERVER="aurora.bayour.com"
AFSCELL="bayour.com"

# --------------
# FUNCTION: Find the partition the volume is on
get_vol_part () {
    local vol=$1
    PART=`vos examine $vol $LOCALAUTH | sed 1d | head -n1 | sed 's@.*/@/@'`
    if [ -z "$PART" ]; then
	# Could not find the partition, try again
	PART=`vos examine $vol $LOCALAUTH | egrep 'server .* partition .* RW Site' | sed -e 's@.*/@/@' -e 's@ .*@@'`
    fi
    [ ! -z "$action" -o ! -z "$verbose" ] && printf "%-65s\n" "Partition for volume $vol is $PART"
}

help () {
    echo "Usage:   `basename $0` [options] [volume]"
    echo "Options: -h,--help		Show this help"
    echo "	 -e,--echo		Don't do anything, just echo the commands"
    echo "	 -v,--verbose		Explain what's to be done"
    exit 0
}

if [ "$#" -lt 1 ]; then
    help
else
    # --------------
    # 'Initialize' AFS access...
    if ! tokens | grep -q ^User; then
	ID=`id -u`
	if [ "$ID" != "0" ]; then
	    echo "You must have a valid AFS token to do a backup (or be root)." > /dev/stderr
	    exit 1
	else
	    LOCALAUTH="-localauth"
	fi
    fi

    # --------------
    # Get the CLI options...
    TEMP=`getopt -o hev --long help,echo,verbose -- "$@"`
    eval set -- "$TEMP"
    while true ; do
	case "$1" in
	    -h|--help)
		help
		;;
	    -e|--echo)
		action='echo'
		shift
		;;
	    -v|--verbose)
		verbose=1
		shift
		;;
	    --)
		shift
		VOL=$1
		break
		;;
	esac
    done
fi

get_vol_part $VOL

# Do the salvage TWICE (just to be safe)!
i=0 ; while [ "$i" -lt 2 ]; do
    echo "Trying to salvage the volume $VOL, on partition $PART"
    $action bos salvage -server ${AFSSERVER:-localhost} -partition $PART -volume $VOL $LOCALAUTH

    i=`expr $i + 1`
done
