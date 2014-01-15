#!/bin/sh

SYSFS=/sys/kernel/scst_tgt
IQN="iqn.2012-11.com.bayour:"

for path in $SYSFS/targets/iscsi/iqn.*; do
    name=`echo $path | sed 's@.*/@@'`
    find $SYSFS/targets/iscsi/$name/sessions/* -type d > /dev/null 2>&1
    if [ "$?" -eq "1" ]; then
	#scstadmin -noprompt -disable_target $name -driver iscsi
	echo 0 > $SYSFS/targets/iscsi/$name/enabled

	#scstadmin -noprompt -close_dev $dev -handler vdisk_blockio
	dev=`/bin/ls -l $SYSFS/targets/iscsi/$name/luns/0/device | sed 's@.*/@@'`
	echo "del_device $dev" > $SYSFS/handlers/vdisk_blockio/mgmt

	#scstadmin -noprompt -rem_target $name -driver iscsi
	echo "del_target $name" > $SYSFS/targets/iscsi/mgmt
    else
	echo "Can't destroy $name - have sessions"
    fi
done
