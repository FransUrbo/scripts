#!/bin/bash

# Get LATEST snapshot for all the filesystems/zvolumes and then
# send this to the remote host.

# Can be used with netcat (faster) or simple 'send | receive'

SSH_OPTS="-24Cx -o ConnectionAttempts=10 -o ConnectTimeout=60"
GET_SNAP="zfs list -H -tsnapshot -oname -d1"
#PORT=9000 # Uncomment to run simple 'send | receive'

#PS_OPT="-Aw"				# *BSD
PS_OPT="faxwww"				# Linux

#NC_OPT_L="-4dvln $SSH_HOST $PORT"	# Listener (*BSD)
NC_OPT_L="-l -p $PORT $SSH_HOST"	# Listener (Linux)

#NC_OPT_R="-nw5"			# Receiver (Linux)
NC_OPT_R="-n"				# Receiver (*BSD)

# ------------------------------------------

function get_local_snap {
    local fs="$1"
    local index=$2

    local i=0
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
    local pids

    if [[ -n "$DSET" ]]; then
	pids=`ssh $SSH_HOST ps $PS_OPT \| grep -E \"nc \.\* $PORT$\|zfs receive \.\* $DSET\" \| grep -v \'grep \' | sed 's@ .*@@'`
	[[ -n "$pids" ]] && ssh $SSH_HOST kill $pids
    fi
}
[[ -n "$PORT" ]] && trap cleanup EXIT

function main {
    local dset="$1"
    local snap_nr=0

    # Get latest local an remote snapshot
    local local_snap=$(get_local_snap "$dset" $snap_nr)
    local remote_snap=$(ssh -n $SSH_HOST $GET_SNAP \"$dset\" 2> /dev/null | tail -n1)
    local progres=$(/bin/ps faxwww | grep -w "${local_snap%@*}\"" | grep -v grep | wc -l)
    progres=$(echo $progres) # Just remove leading zeros...

    if [[ -n "$DEBUG" ]]; then
	echo "zfs send -p \"$local_snap\" | ssh $SSH_OPTS $SSH_HOST zfs receive -uvF \"$dset\""
    elif [[ -z "$local_snap" ]]; then
	return 1
    elif [[ -z "$remote_snap" || "$local_snap" != "$remote_snap" ]] && [[ "$progres" == 0 ]]; then
	# No remote snapshot for this filesystem/volume
	# OR
	# The latest remote does not match the name of the latest local snapshot

	if [[ -z "$PORT" ]]; then
	    # Simple, no-nonsence send | receive
	    zfs send -p "$local_snap" | \
		ssh $SSH_OPTS $SSH_HOST zfs receive -uvF \"$dset\"
	    if [[ "$?" != "0" ]]; then
		((snap_nr += 1))
		main "$dset" $snap_nr
	    fi
	else
	    local ret=0 ; rm -f /tmp/rcv.$$*

	    # Just to make sure that cleanup() don't kill something that shouldn't be killed!
	    local DSET="$dset"

	    # Startup a receiver on the remote host
	    (ssh -n $SSH_HOST nc $NC_OPT_L \| zfs receive -uvF \"$dset\" 2>&1 | tee /tmp/rcv.$$-1) &

	    # Just make sure the receiver is up and running!
	    sleep 2
	    pid=$(/bin/ps faxwww | egrep "ssh .* nc .* zfs receive .*$DSET" | grep -v 'grep ' | sed 's@ [a-z].*@@')

	    # Send the snapshot to netcat, which sends it to netcat on the receiver.
	    (zfs send -p "$local_snap" | nc $NC_OPT_R $SSH_HOST $PORT 2>&1 | tee /tmp/rcv.$$-2)

	    # Cleanup local and remote (kill all process regarding this snapshot).
	    # - netcat doesn't shutdown after the send/receive is completed...
	    [[ -n "$pid" ]] && kill $pid

	    # NOTE: Don't kill remote if send gave error - reuse this for the next snapshot in list...
	    grep -Eq 'invalid backup stream|Invalid exchange|invalid name' /tmp/rcv.$$* && ret=1

	    if [[ "$ret" -eq "1" ]]; then
		((snap_nr += 1))
		main "$dset" $snap_nr
	    else
		local pids=`ssh $SSH_HOST ps $PS_OPT \| grep -E \"nc \.\* $PORT$\|zfs receive \.\* $dset\"$" \| grep -v \'grep \' | sed 's@ .*@@'`
		[ -n "$pids" ] && ssh $SSH_HOST kill $pids
	    fi
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
zfs list -H -tfilesystem,volume -oname -r share/VirtualMachines |
    while read dset; do
	main "$dset"
    done
