#!/bin/sh

# --------------
# Set some default variables
AFSSERVER="papadoc.bayour.com"
AFSCELL="bayour.com"

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
if [ ! -z "$1" ]; then
    TEMP=`getopt -o hf --long help,noformat -- "$@"`
    eval set -- "$TEMP"
    while true ; do
	case "$1" in
	    -h|--help)
		echo "Usage:   `basename $0` [option]"
		echo "Options: -h,--help		Show this help"
		echo "         -f,--noformat	Don't use tabs, separate colums with :"
		exit 0
		;;
	    -f|--noformat)	NOFORMAT=1 ; shift ;;
	    --)			shift ; VOLUMES="$*" ; break ;; 
	    *)			echo "Internal error!" ; exit 1 ;;
	esac
    done
fi
    
# --------------
set -- `vos listpart ${AFSSERVER:-localhost} | grep -v '^[A-Z]'`
PARTITIONS="$*"
for part in $PARTITIONS; do
    set -- `mount | grep $part`
    dev="$1"

    vos listvol ${AFSSERVER:-localhost} $part | grep '^[a-z]' | \
    while read line; do
	set -- `echo $line`

	# /vicepc  : user.jerry                     :  536871002 : RW :       10K : On-line
	if [ -z "$NOFORMAT" ]; then
	    printf "%-10s %-8s %-30s %10s %-2s %8d%s %s\n" $dev $part $1 $2 $3 $4 $5 $6
	else
	    printf "%s;%s;%s;%s;%s;%d%s;%s\n" $dev $part $1 $2 $3 $4 $5 $6
	fi
    done
done

