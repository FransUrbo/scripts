#!/bin/sh

#aurora:/proc/scsi/sym53c8xx# echo "resetdev 10" > 4
#aurora:/proc/scsi/sym53c8xx# echo "scsi add-single-device 4 0 10 0" > /proc/scsi/scsi

if [ -z "$1" -o -z "$2" ]; then
    echo "Usage: add|rem CONTROLLER:ID"
    exit 1
fi

cmd=$1

set -- `echo $2 | sed 's@:@ @'`
CONTROLLER=$1 ; ID=$2

if [ -z "$CONTROLLER" -o -z "$ID" ]; then
    echo "Usage: CONTROLLER:ID"
    exit 1
fi

if [ ! -f "/proc/scsi/sym53c8xx/$CONTROLLER" ]; then
    echo "Controller does not exist!"
    echo "Usage: CONTROLLER:ID"
    exit 1
fi

if [ "$cmd" == "add" ]; then
    echo "resetdev $ID" > /proc/scsi/sym53c8xx/$CONTROLLER
    echo "scsi add-single-device $CONTROLLER 0 $ID 0" > /proc/scsi/scsi
elif [ "$cmd" == "rem" ]; then
    echo "scsi remove-single-device $CONTROLLER 0 $ID 0" > /proc/scsi/scsi
    echo "resetdev $ID" > /proc/scsi/sym53c8xx/$CONTROLLER
fi
