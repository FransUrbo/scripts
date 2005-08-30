#!/bin/sh

count=0

mysql -h mysql -u bacula --password=BaCuLa bacula -Br -e \
"SELECT JobId,Name,StartTime,EndTime,Type,Level,JobFiles,JobBytes,JobStatus \
FROM Job WHERE NOT JobBytes='0' ORDER BY StartTime" | \
while read line; do
    set -- `echo $line`

    if [ "$count" == "0" ]; then
	# Header
	printf "%6s %-18s %-21s %-21s %5s %7s %12s %9s\n" $1 $2 $3 $4 $6 $7 $8 $9
    else
	case "$8" in
	    D) type="Diff";;
	    I) type="Incr";;
	    F) type="Full";;
	    *) type="$8";;
	esac
	printf "%6s %-18s %-10s %-10s %-10s %-10s %-4s %9s " $1 $2 $3 $4 $5 $6 $type $9

	i=1
	while [ $i -le 9 ]; do
	    shift
	    i=`expr $i + 1`
	done

	case "$2" in
	    A) stat="Canceled";;
	    T) stat="Ok";;
	    E) stat="Error";;
	    *) stat="$2";;
	esac
	printf "%12s %-9s\n" $1 $stat
    fi

    count=`expr $count + 1`
done

# _ALL_ jobs:
#"SELECT JobId,Name,StartTime,Type,Level,JobFiles,JobBytes,JobStatus FROM Job ORDER BY StartTime"