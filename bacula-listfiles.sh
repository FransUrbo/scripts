#!/bin/sh

if [ -z "$1" ]; then
    echo "Usage: `basename $0` [jobid]"
    exit 1
fi

mysql -h mysql -u bacula --password=BaCuLa bacula -Br -e \
"SELECT \
CONCAT(Path.Path,Filename.Name) \
AS Path \
FROM File,Filename,Path \
WHERE File.JobId=$1 AND Filename.FilenameId=File.FilenameId AND Path.PathId=File.PathId"
