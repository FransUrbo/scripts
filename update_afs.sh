#!/bin/sh

# $Id: update_afs.sh,v 1.5 2002-08-29 13:57:03 turbo Exp $

cd /

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
VOLUMES="" ; TEMP=`getopt -o hupcvt --long help,users,public,common,verbose,test -- "$@"`
eval set -- "$TEMP"
while true ; do
    case "$1" in
	-h|--help)
	    echo "Usage:   `basename $0` [option] [volume]"
	    echo "Options: -h,--help		Show this help"
	    echo "	 -u,--users		Release only the user.* volumes"
	    echo "	 -p,--public		Release only the public.* volumes"
	    echo "	 -c,--common		Release only the common.* volumes"
	    echo "	 -v,--verbose		Explain what's being done"
	    echo "	 -t,--test		Get volumes, but don't relase them"
	    echo "If volume is given, only release that/those volumes."
	    echo "If no option and no volume is given, backup all replicated volumes."
	    echo 
	    exit 0
	    ;;
	-c|--common)		search="$search common" ; shift ;;
	-u|--users)		search="$search user"   ; shift ;;
	-p|--public)		search="$search public" ; shift ;;
	-v|--verbose)		verbose=1 ; shift ;;
	-t|--test)		test=1	  ; shift ;;
	--)			shift ; [ -z "$VOLUMES" ] && VOLUMES="$*" ; break ;; 
	*)			echo "Internal error!" ; exit 1 ;;
    esac
done

# --------------
# Get volumes for backup
if [ "$search" != "" ]; then
    # Build a nice regexp for the volumes to search for.
    search="^(`echo $search | sed -e 's@ @\\\..*\\\.readonly|^@' -e 's@\$@\\\..*\\\.readonly@'`).*RO.*"

    # Get all the volumes contain the search criteria
    VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet $LOCALAUTH | egrep "$search" | sed -e 's@\.readonly.*@@'`
else
    if [ -z "$VOLUMES" ]; then
	VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet $LOCALAUTH | grep readonly | sed -e 's@\ .*@@' -e 's@\.readonly@@'`
    fi
fi
VOLUMES=`echo $VOLUMES`

if [ ! -z "$test" ]; then
    echo "Volumes to release: $VOLUMES"
    exit 0
fi

for vol in $VOLUMES; do
    [ ! -z "$verbose" ] && echo -n "Releasing volume: $vol"
    RES=`vos release $vol $LOCALAUTH 2>&1`
    res=$?
    if [ "$res" != "0" ]; then
	# An error occured!
	RES=`echo $RES | sed 's@Could not lock.*@@'`
	echo "ERROR: Could not release volume $vol - $res/$RES"
    else
	[ ! -z "$verbose" ] && echo " -> $res"
    fi
done
