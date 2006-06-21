#!/bin/sh

# $Id: bacula-statusjobs.sh,v 1.1 2006-06-21 11:08:25 turbo Exp $

if [ -f "/etc/bacula/.conn_details" ]; then
   . /etc/bacula/.conn_details
else
    echo "Config file /etc/bacula/.conn_details does not exists!"
    exit 1
fi

# --------------
help () {
    echo "Usage:   `basename $0` <-c [client]> <-j [jobname]>"
    echo "Options: -h,--help    Show this help"
    echo "         -c,--client  Backup client"
    echo "         -j,--job     Backup client job name"
    exit 1
}

# --------------
# Get the CLI options...
client="%" ; jobname="%"
if [ -n "$1" ]; then
    TEMP=`getopt -o ahc:j: --long help,all,client:,job: -- "$@"`
    eval set -- "$TEMP"
    while true ; do
	case "$1" in
	    -a|-all)		client="%" ; jobname="%" ; shift ;;
	    -h|--help)		help ;;
	    -c|--client)	client="`echo $2`%" ; shift 2 ;;
	    -j|--job)		jobname="`echo $2`%" ; shift 2 ;;
	    --)			shift ; break ;;
	    *)			echo "Internal error!" ; exit 1 ;
	esac
    done
fi

# ==============================================================================

if [ "$CATALOG" = "mysql" ]; then
    COMMAND="mysql -h $HOST -u $USERNAME --password=$PASSWORD $DB -BNr -e "
else
    echo "PostgreSQL not yet availible. Please edit $0"
    exit 1
fi

# Output a header
# Pumba_System    2005-09-29 01:09:41     2005-09-29 01:16:22     1690    861142479
printf "%-18s %-22s %-22s %-6s %-13s\n" Jobname Jobstart Jobend SDFiles SDBytes

# Get clients
$COMMAND "SELECT ClientId,Name FROM Client WHERE Name LIKE '$client'" | \
while read line_clients; do
    set -- `echo $line_clients`
    id=$1 ; name=$2

    # Setup query to retreive status for all jobs on this client
    QUERY="SELECT Name,StartTime,EndTime,JobFiles,JobBytes FROM Job WHERE \
ClientId=$id AND JobErrors=0 AND NOT (Name='RestoreFiles') AND NOT (Name='Backup_Old') \
AND Name LIKE '$jobname' ORDER BY Name,StartTime"

    # Get status for all jobs on this client
    $COMMAND "$QUERY" | \
    while read line_jobs; do
	set -- `echo $line_jobs`

	# Pumba_System    2005-09-29 01:09:41     2005-09-29 01:16:22     1690    861142479
	name=$1 ; start_date=$2 ; start_time=$3 ; end_date=$4 ; end_time=$5 ; files=$6 ; bytes=$7

	printf "%-18s %-10s %-8s    %-10s %-8s    %6s %13s\n" $name $start_date $start_time $end_date $end_time $files $bytes
    done
done
