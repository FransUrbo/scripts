#!/bin/sh

# $Id: update_afs.sh,v 1.14 2003-10-22 05:25:38 turbo Exp $

cd /

# --------------
# Set some default variables
AFSSERVER="papadoc.bayour.com"
AFSCELL="bayour.com"

# --------------
replicated () {
    rw=$1 ; ro=$rw\.readonly

    set -- `vos examine $rw $LOCALAUTH -encrypt | grep 'Last Update'`
    shift ; shift
    time1=`date -d "$*" "+%s"`

    set -- `vos examine $ro $LOCALAUTH -encrypt | grep 'Last Update'`
    shift ; shift
    time2=`date -d "$*" "+%s"`

    [ ! -z "$verbose" -a ! -z "$test" ] && printf "Vol: %-25s - $time1 ; $time2 => " $rw
    if [ $time1 -ge $time2 ]; then
	[ ! -z "$verbose" -a ! -z "$test" ] && echo "Needs to be released."
	return 1
    else
	[ ! -z "$verbose" -a ! -z "$test" ] && echo "no need for release."
	return 0
    fi
}

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
VOLUMES="" ; TEMP=`getopt -o chprtuvV --long common,help,public,root,test,users,verbose,version -- "$@"`
eval set -- "$TEMP"
while true ; do
    case "$1" in
	-c|--common)		search="$search common" ; shift ;;
	-h|--help)
	    echo "Usage:   `basename $0` [option] [volume]"
	    echo "Options:"
	    echo "	-c,--common	Release only the common.* volumes"
	    echo "	-h,--help	Show this help"
	    echo "	-p,--public	Release the public.* volumes"
	    echo "	-r,--root	Release the root.* volumes"
	    echo "	-t,--test	Get volumes, but don't relase them"
	    echo "	-u,--users	Release the user.* volumes"
	    echo "	-v,--verbose	Explain what's being done"
	    echo "	-V,--version	Show version number"
	    echo "If volume is given, only release that/those volumes."
	    echo "If no option and no volume is given, backup all replicated volumes."
	    echo 
	    exit 0
	    ;;
	-p|--public)	search="$search public" ; shift ;;
	-r|--root)	search="$search root" 	; shift ;;
	-t|--test)	test=1 ; shift ;;
	-u|--users)	search="$search user"   ; shift ;;
	-v|--verbose)	verbose="-verbose"	; shift ;;
	-V|--version)
	    set -- `echo "$Id: update_afs.sh,v 1.14 2003-10-22 05:25:38 turbo Exp $"`
	    echo "Version: $3"
	    exit 0
	    ;;
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
    VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet $LOCALAUTH -encrypt | egrep "$search" | sed -e 's@\.readonly.*@@'`
else
    if [ -z "$VOLUMES" ]; then
	VOLUMES=`vos listvol ${AFSSERVER:-localhost} -quiet $LOCALAUTH -encrypt | grep readonly | sed -e 's@\ .*@@' -e 's@\.readonly@@'`
    fi
fi
VOLUMES=`echo $VOLUMES`

# --------------
# Which of these should REALLY be released?
# Look in the 'Last Update' line of 'vos examine'.
#
# If the RW volume is _NEWER_ than the RO, then replicate!
for vol in $VOLUMES; do
    if ! replicated $vol; then
	RELEASE="$RELEASE $rw"
    fi
done
VOLUMES="`echo $RELEASE | sed 's@^\ @@'`"

if [ ! -z "$test" ]; then
    [ ! -z "$verbose" ] && spcs="             "
    echo "Volumes to release: $spcs$VOLUMES"
    exit 0
fi

for vol in $VOLUMES; do
    if [ ! -z "$verbose" ]; then
	S=`date +"%Y%m%d %H:%M:%S"` ; START=`date +"%s"`
	echo "Releasing volume $volume ($S): "
	vos release $vol $LOCALAUTH $verbose -encrypt

	E=`date +"%Y%m%d %H:%M:%S"` ; END=`date +"%s"`
	SEC=`expr $END - $START` ; MIN=`expr $SEC / 60`

	echo "Volume released at $E. Took $SEC sec (~$MIN min)"
    else
	RES=`vos release $vol $LOCALAUTH -encrypt 2>&1`
    fi

    res=$?
    if [ "$res" != "0" ]; then
	# An error occured!
	RES=`echo $RES | sed 's@Could not lock.*@@'`
	echo "ERROR: Could not release volume $vol - $res/$RES"
    else
	[ ! -z "$verbose" ] && echo
    fi
done
