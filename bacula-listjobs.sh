#!/bin/sh

# $Id: bacula-listjobs.sh,v 1.2 2006-06-21 10:28:39 turbo Exp $

if [ -f "/etc/bacula/.conn_details" ]; then
    . /etc/bacula/.conn_details
else
    echo "Config file /etc/bacula/.conn_details does not exists!"
    exit 1
fi

if [ "$CATALOG" = "mysql" ]; then
    COMMAND="mysql -h $HOST -u $USERNAME --password=$PASSWORD $DB -E -e"
else
    echo "PostgreSQL not yet availible. Please edit $0"
    exit 1
fi

COLS="JobId,Name,StartTime,EndTime,Type,Level,JobFiles,JobBytes,JobStatus"
ORDER="ORDER BY StartTime"

if [ -n "$1" ]; then
    # Get MediaId for this VolumeName
    MEDIAID=`$COMMAND "select MediaId from Media where VolumeName='$1'" | grep -v MediaId`
    if [ -z "$MEDIAID" ]; then
	echo "No such media!"
	exit 1
    fi
	
    # Get all JobId's for this Volume
    JOBID=`$COMMAND "SELECT DISTINCT JobId FROM JobMedia WHERE MediaId=$MEDIAID ORDER BY JobId" | grep -v JobId`
    if [ -z "$JOBID" ]; then
	echo "No jobs associated with this media!"
	exit 1
    fi
	
    # Get information for all these JobId's
    SQL="SELECT $COLS FROM Job WHERE NOT JobBytes='0' AND ("
    for jobid in $JOBID; do
	SQL="$SQL JobId='$jobid' OR "
    done
    SQL="`echo $SQL | sed 's@ OR$@ )@'`" # Remove the last (empty) ' OR'.
    SQL="$SQL $ORDER" # Add select order
else
    # Get information on ALl jobs
    SQL="SELECT $COLS FROM Job WHERE NOT JobBytes='0' $ORDER"
fi

printed_full_header=0
count=1
    
$COMMAND "$SQL" | grep -v '^\*\*\*\*' | \
while read line; do
    set -- `echo $line`
	
    header=`echo $1 | sed 's@:$@@'`
    shift
    data=`echo $*`
#    printf "Header: '$header'\nData: '$data'\n"
	
    if [ "$printed_full_header" == "0" ]; then
	# Header
	case "$count" in
	    1)  printf "%6s "   $header
		jobid=$data;;
		    
	    2)  printf "%-25s " $header
		name=$data;;
		    
	    3)  printf "%-20s " $header
		starttime=$data;;
		    
	    4)  printf "%-20s " $header
		endtime=$data;;
		    
	    6)  printf "%-10s " $header
		case "$data" in
		    B) level="Base";;
		    D) level="Diff";;
		    F) level="Full";;
		    I) level="Incr";;
		    *) level="$data";;
		esac
		;;
		    
	    7)  printf "%-10s "   $header
		jobfiles=$data;;
		    
	    8)  printf "%14s "  $header
		jobbytes=$data;;
		    
	    9)  printf "%9s\n"   $header
		case "$data" in
		    A) jobstatus="Canceled";;
		    T) jobstatus="Ok";;
		    E) jobstatus="Error";;
		    f) jobstatus="Failed";;
		    *) jobstatus="$data";;
		esac
		    
		printed_full_header=1
		count=0;;
	esac
    elif [ -n "$jobid" -a -n "$name" -a -n "$starttime" -a \
	   -n "$endtime" -a -n "$level" -a -n "$jobfiles" -a \
	   -n "$jobbytes" -a -n "$jobstatus" ]; then
	printf "%6s %-25s %-20s %-20s %-7s %11s %16s %-5s\n" \
		$jobid "$name" "$starttime" "$endtime" $level \
		$jobfiles $jobbytes $jobstatus
		    
	jobid= ; name= ; starttime= ; endtime= ; level=
	jobfiles= ; jobbytes= ; jobstatus=
    else
	case "$count" in
	    1)  jobid=$data;;
	    2)  name=$data;;
	    3)  starttime=$data;;
	    4)  endtime=$data;;
	    6)  case "$data" in
		    B) level="Base";;
		    D) level="Diff";;
		    F) level="Full";;
		    I) level="Incr";;
		    *) level="$data";;
	        esac
	        ;;
		    
	    7)  jobfiles=$data;;
	    8)  jobbytes=$data;;
	    9)  case "$data" in
		    A) jobstatus="Canceled";;
		    T) jobstatus="Ok";;
		    E) jobstatus="Error";;
		    f) jobstatus="Failed";;
		    *) jobstatus="$data";;
	        esac
	        count=0;;
	esac
    fi
	
    count=`expr $count + 1`
done

