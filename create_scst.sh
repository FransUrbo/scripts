#!/bin/sh

# debianzfs-scst:/sys/kernel/scst_tgt# lsmod | grep scst
# iscsi_scst             68378  5 
# scst_vdisk             44538  0 
# libcrc32c                954  2 iscsi_scst,scst_vdisk
# scst                  208565  2 iscsi_scst,scst_vdisk
# scsi_mod              156768  7 scst,ib_iser,iscsi_tcp,libiscsi,scsi_transport_iscsi,sd_mod,libata

SYSFS=/sys/kernel/scst_tgt
IQN="iqn.2012-11.com.bayour:"

echo 1 > $SYSFS/targets/iscsi/enabled
for i in {1..40}; do
    vol=share/tests/iscsi$i
    id=`echo "$vol" | sed 's@/@\.@g'`
    dev=`echo "$vol" | sed 's@.*/@@'`

    name=$IQN$id

#    scstadmin -add_target $name -driver iscsi
    echo "add_target $name" > $SYSFS/targets/iscsi/mgmt

#    scstadmin -open_dev $dev -handler vdisk_blockio -attributes filename=/dev/zvol/$vol,blocksize=512
    echo "add_device $dev filename=/dev/zvol/$vol; blocksize=512" > $SYSFS/handlers/vdisk_blockio/mgmt

#    scstadmin -add_lun 0 -target $name -driver iscsi -device $dev
    echo "add $dev 0" > $SYSFS/targets/iscsi/$name/luns/mgmt

#    scstadmin -enable_target $name -driver iscsi 
    echo 1 > $SYSFS/targets/iscsi/$name/enabled

    /sbin/zfs_share_iscsi "$name"

    exit 0
done
