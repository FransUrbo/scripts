#!/bin/sh

# --------------
# Set some default variables
AFSSERVER="aurora.bayour.com"
AFSCELL="bayour.com"

# --------------
# 'Initialize' AFS access...
ID=`id -u`
if [ "$ID" = "0" ]; then
    LOCALAUTH="-localauth"
else
    if ! tokens | grep -q ^User; then
	echo "You must have a valid AFS token (or be root)." > /dev/stderr
	exit 1
    fi
fi

# --------------
# Get the CLI options...
if [ ! -z "$1" ]; then
    TEMP=`getopt -o hfv --long help,noformat,volumes -- "$@"`
    eval set -- "$TEMP"
    while true ; do
	case "$1" in
	    -h|--help)
		echo "Usage:   `basename $0` [option]"
		echo "Options: -h,--help        Show this help"
		echo "         -f,--noformat    Don't use tabs, separate colums with :"
		echo "         -v,--volumes     List only volume names"    
		exit 0
		;;
	    -f|--noformat)	NOFORMAT=1 ; shift ;;
	    -v|--volumes)	VOLUMES_ONLY=1 ; shift ;;
	    --)			shift ; AFSSERVER="$1" ; break ;; 
	    *)			echo "Internal error!" ; exit 1 ;;
	esac
    done
fi

TMPFILE=`tempfile -p lst.`
    
# --------------
set -- `vos listpart ${AFSSERVER:-localhost} $LOCALAUTH | grep -v '^[A-Z]'`
PARTITIONS="$*"
for part in $PARTITIONS; do
    set -- `mount | grep $part`
    dev="$1"
    if [ -z "$dev" -a -z "$VOLUMES_ONLY" ]; then
	dev="[remote]"
    fi

    echo 0 > $TMPFILE

    vos listvol ${AFSSERVER:-localhost} $part $LOCALAUTH | grep '^[a-z]' | \
    while read line; do
	echo 1 > $TMPFILE

	set -- `echo $line`
	if [ ! -z "$VOLUMES_ONLY" ]; then
	    printf "%s\n" $1
	elif [ ! -z "$NOFORMAT" ]; then
	    printf "%s;%s;%s;%s;%s;%d%s;%s\n" $dev $part $1 $2 $3 $4 $5 $6
	else
	    printf "%-10s %-8s %-30s %10s %-2s %8d%s %s\n" $dev $part $1 $2 $3 $4 $5 $6
	fi
    done

    gotvols=`cat $TMPFILE`
    [ -z "$NOFORMAT" -a "$gotvols" != 0 -a -z "$VOLUMES_ONLY" ] && echo
done
rm $TMPFILE
