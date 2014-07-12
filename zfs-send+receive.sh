#!/bin/bash

# Get LATEST snapshot for all the filesystems/zvolumes and then
# send this to the remote host.

# Can be used with netcat (faster) or simple 'send | receive'

SSH_OPTS="-24Cx -o ConnectionAttempts=10 -o ConnectTimeout=60"
GET_SNAP="zfs list -H -tsnapshot -oname -d1"
#PORT=$$ # Uncomment to run simple 'send | receive'

# ------------------------------------------

function get_local_snap {
    fs="$1"
    index=$2

    i=0
    $GET_SNAP "$dset" 2> /dev/null | \
	sort -r | \
	{ while read snaps; do
	    eval SNAP_$i=\"$snaps\"
	    ((i += 1))
	    done 

	    eval echo \$SNAP_$index
	}
}

# Cleanup remote host
function cleanup {
    if [ -n "$DSET" ]; then
	ssh $SSH_HOST ps -Aw \| grep -E \"nc \.\* $PORT$\|zfs receive \.\* $DSET\" \| grep -v \'grep \'

	pids=`ssh $SSH_HOST ps -Aw \| grep -E \"nc \.\* $PORT$\|zfs receive \.\* $DSET\" \| grep -v \'grep \' | sed 's@ .*@@'`
	[ -n "$pids" ] && ssh $SSH_HOST kill $pids
    fi
}
[ -n "$PORT" ] && trap cleanup EXIT

function main {
    dset="$dset"
    snap_nr=$2

    # Get latest local an remote snapshot
    local_snap=$(get_local_snap "$dset" $snap_nr)
    remote_snap=$(ssh -n $SSH_HOST $GET_SNAP \"$dset\" 2> /dev/null | tail -n1)
    progres=$(/bin/ps faxwww | grep -w "${local_snap%@*}\"" | grep -v grep | wc -l)

    if [[ -n "$DEBUG" ]]; then
	echo "zfs send \"$local_snap\" | ssh $SSH_OPTS $SSH_HOST zfs receive -uvF \"$dset\""
    elif [[ -z "$local_snap" ]]; then
	return 1
    elif [[ -z "$remote_snap" || "$local_snap" != "$remote_snap" ]] && [[ "$progres" == 0 ]]; then
	# No remote snapshot for this filesystem/volume
	# OR
	# The latest remote does not match the name of the latest local snapshot

	if [ -z "$PORT" ]; then
	    # Simple, no-nonsence send | receive
	    zfs send "$local_snap" | \
		ssh $SSH_OPTS $SSH_HOST zfs receive -uvF \"$dset\"
	    if [ "$?" != "0" ]; then
		((snap_nr += 1))
		main "$dset" $snap_nr
	    fi
	else
	    # Just to make sure that cleanup() don't kill something that shouldn't be killed!
	    DSET="$dset"

	    # Startup a receiver on the remote host
	    ssh -n $SSH_HOST nc -4dvln $SSH_HOST $PORT \| zfs receive -uvF \"$dset\" &

	    # Just make sure the receiver is up and running!
	    sleep 2
	    pid=$(/bin/ps faxwww | egrep "ssh .* nc .* zfs receive .*$DSET" | grep -v 'grep ' | sed 's@ [a-z].*@@')

	    # Send the snapshot to netcat, which sends it to netcat on the receiver.
	    zfs send "$local_snap" | nc -nw5 $SSH_HOST $PORT

	    # Cleanup local and remote (kill all process regarding this snapshot).
	    # - netcat doesn't shutdown after the send/receive is completed...
	    [ -n "$pid" ] && kill $pid

	    pids=`ssh $SSH_HOST ps -Aw \| grep -E \"nc \.\* $PORT$\|zfs receive \.\* $dset\" \| grep -v \'grep \' | sed 's@ .*@@'`
	    [ -n "$pids" ] && ssh $SSH_HOST kill $pids
	fi
    fi
}

# ------------------------------------------

# Get options (basically only the remote host)
if [ -z "$1" ]; then
    echo "Usage: `basename $0` <remote host>"
    exit 1
else
    SSH_HOST="$1"

    # Check to make sure we can reach the host
    ping -c5 $SSH_HOST > /dev/null
    if [ "$?" == 1 ]; then
	echo "Can't reach $SSH_HOST"
	exit 1
    fi
fi

# List all filesystems and volumes, get only the NAME column
#zfs list -H -tfilesystem,volume -oname |
cat /tmp/zfs_list.txt |
    while read dset; do
	main "$dset" 0
    done
