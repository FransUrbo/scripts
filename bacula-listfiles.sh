#!/bin/sh

# $Id: bacula-listfiles.sh,v 1.2 2006-06-21 10:20:53 turbo Exp $

if [ -z "$1" ]; then
    echo "Usage: `basename $0` <jobid>"
    exit 1
else
    jobid=$1
fi

if [ -f "/etc/bacula/.conn_details" ]; then
    . /etc/bacula/.conn_details
else
    echo "Config file /etc/bacula/.conn_details does not exists!"
    exit 1
fi

if [ "$CATALOG" = "mysql" ]; then
    COMMAND="mysql -h $HOST -u $USERNAME --password=$PASSWORD $DB -Br -e "
else
    echo "PostgreSQL not yet availible. Please edit $0"
    exit 1
fi

$COMMAND "SELECT CONCAT(Path.Path,Filename.Name) AS Path FROM File,Filename,Path \
WHERE File.JobId=$jobid AND Filename.FilenameId=File.FilenameId AND Path.PathId=File.PathId"
