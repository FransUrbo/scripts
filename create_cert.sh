#!/bin/sh

# $Id: create_cert.sh,v 1.3 2005-03-19 13:04:23 turbo Exp $

BASE_DIR=/etc/ssl
BASE_CFG=$BASE_DIR/openssl.cnf

# Default config file. One without aliases
cfg=$BASE_CFG-0

# How many aliases to support
max=2

# Figure out which config file we should use. This depends
# on if we use alias(es) or not...
cnt=1
while [ $cnt -le $max ]; do
    # Extract ALIAS_NAMEx from the environment
    var1="ALIAS_NAME$cnt"
    var2="alias$cnt"

    val1=`eval echo "$"$var1`

    if [ -z "$val1"  ]; then
	read -p "Alias $cnt: " -t 10 tmp
    else
	tmp=$val1
    fi
    eval `echo $var2=$tmp` # alias$cnt=$tmp
    eval `echo $var1=$tmp` # ALIAS_NAME$cnt=$tmp

    export `echo $var1`    # export ALIAS_NAME$cnt

    if [ ! -z "$tmp" ]; then
	cfg=$BASE_CFG-$cnt
    fi

    cnt=`expr $cnt + 1`
done
cfg="-config $cfg"

# Create a temporary directory
TMPDIR=`tempfile`
rm -f $TMPDIR
mkdir $TMPDIR
cd $TMPDIR

# Skapa cert req (five year)
openssl req $cfg -nodes -new -days 1825 -out server_req.pubkey -keyout server.privkey

# Signera cert requesten med CA certet
openssl ca $cfg -in server_req.pubkey -out server.pubkey

if [ -f "server.pubkey" ]; then
    rm server_req.pubkey
    chmod 644 server.privkey server.pubkey
    
    FILENAME=`egrep 'Subject:.*CN=' server.pubkey | sed -e 's@.*CN=@@' -e 's@/.*@@' -e 's@\.@_@g'`
    if [ ! -z "$FILENAME" ]; then
	cat server.pubkey server.privkey > $FILENAME.pem
	mv server.privkey $FILENAME.prv
	mv server.pubkey $FILENAME.pub

	echo "Moving files to cert database directory:"
	[ ! -d "$BASE_DIR/certs/" ] && mkdir -p $BASE_DIR/certs
	cp -v $FILENAME.pem $FILENAME.prv $FILENAME.pub $BASE_DIR/certs/
	if [ "$?" = "0" ]; then
	    cd /
	    rm -Rf $TMPDIR
	fi

	exit 0
    else
	error="Something went wrong. Couldn't figure out filename..."
    fi
else
    error="Could not generate public key for some reason."
fi

if [ ! -z "$error" ]; then
    echo
    echo $error
    echo "Tempdir is: $TMPDIR"
    exit 1
fi
