#!/bin/sh

echo "===> iSCSI"
list_scst.pl

echo

echo "===> SMB"
list_smbfs.sh

echo

echo "===> NFS"
list_nfs.sh

