#!/bin/sh

cd /

# --------------
# Set some default variables
AFSSERVER="papadoc.bayour.com"
AFSCELL="bayour.com"
#LOCALAUTH="-localauth"

# --------------
# Get the CLI options...
VOLUMES="" ; TEMP=`getopt -o hupcv --long help,users,public,common,verbose -- "$@"`
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
	    echo "If volume is given, only release that/those volumes."
	    echo "If no option and no volume is given, backup all replicated volumes."
	    echo 
	    exit 0
	    ;;
	-c|--common)		VOLUMES="common" ; shift ;;
	-u|--users)		VOLUMES="user"   ; shift ;;
	-p|--public)		VOLUMES="public" ; shift ;;
	-v|--verbose)		verbose=1        ; shift ;;
	--)			shift ; [ -z "$VOLUMES" ] && VOLUMES="$*" ; break ;; 
	*)			echo "Internal error!" ; exit 1 ;;
    esac
done

# --------------
# Get volumes for backup
if [ "$VOLUMES" != "" ]; then
    VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet $LOCALAUTH | grep "^$VOLUMES\..*\.readonly" | sed -e 's@\ .*@@' -e 's@\.readonly@@'`
else
    if [ -z "$VOLUMES" ]; then
	VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet $LOCALAUTH | grep readonly | sed -e 's@\ .*@@' -e 's@\.readonly@@'`
    fi
fi
VOLUMES=`echo $VOLUMES`

for vol in $VOLUMES; do
    [ ! -z "$verbose" ] && echo -n "Releasing volume: $vol"
    RES=`vos release $vol 2>&1`
    res=$?
    if [ "$res" != "0" ]; then
	# An error occured!
	echo "Could not release volume $vol - $res/$RES"
    else
	[ ! -z "$verbose" ] && echo " -> $res"
    fi
done
