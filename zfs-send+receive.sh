#!/bin/bash

#SSH_HOST="freenas.bayour.com"
SSH_HOST="192.168.69.45"
SSH_OPTS="-24Cx -o ConnectionAttempts=10 -o ConnectTimeout=60 -c arcfour128"
GET_SNAP="zfs list -H -tsnapshot -oname -d1"
PORT=6969

# Cleanup
function cleanup {
	pids=`ssh $SSH_HOST ps -A \| grep -E \'nc \|zfs receive \' \| grep -v \'grep \' | sed 's@ .*@@'`
	[ -n "$pids" ] && ssh $SSH_HOST kill $pids

}
trap cleanup EXIT ERR

# List all filesystems and volumes, get only the NAME column
zfs list -H -tfilesystem,volume -oname |
    while read dset; do
	# Get latest local an remote snapshot
	local_snap=$($GET_SNAP "$dset" 2> /dev/null | tail -n1)
	remote_snap=$(ssh -n $SSH_HOST $GET_SNAP \"$dset\" 2> /dev/null | tail -n1)
	progres=$(/bin/ps faxwww | grep -w "${local_snap%@*}\"" | grep -v grep | wc -l)

	if [[ -z "$remote_snap" || "$local_snap" != "$remote_snap" ]] && [[ "$progres" == 0 ]]; then
	    # No remote snapshot for this filesystem/volume
	    # OR
	    # The latest remote does not match the name of the latest local snapshot

#	    zfs send "$local_snap" | \
#		ssh $SSH_OPTS $SSH_HOST zfs receive -uvF \"$dset\"

#echo "ssh -n $SSH_HOST nc -4dvlnw5 $SSH_HOST $PORT \| zfs receive -uvF \"$dset\""
		ssh -n $SSH_HOST nc -4dvlnw5 $SSH_HOST $PORT \| zfs receive -uvF \"$dset\" &
		pid="$!"

		sleep 2

#echo "zfs send \"$local_snap\" | nc $SSH_HOST $PORT"
		zfs send "$local_snap" | nc -n $SSH_HOST $PORT

		kill $pid
		cleanup
	fi
    done
