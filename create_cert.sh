#!/bin/sh

# $Id: create_cert.sh,v 1.1 2004-01-13 06:59:59 turbo Exp $

if [ -z "$ALIAS_NAME1" -o -z "$ALIAS_NAME2" ]; then
    echo "Please set the variables ALIAS_NAME1, ALIAS_NAME2!"
#    exit 1
fi

TMPDIR=`tempfile`
rm -f $TMPDIR
mkdir $TMPDIR
cd $TMPDIR

# Skapa cert req (five year)
openssl req -nodes -new -days 1825 -out server_req.pubkey -keyout server.privkey

# Signera cert requesten med CA certet
openssl ca -in server_req.pubkey -out server.pubkey

rm server_req.pubkey
chmod 644 server.privkey server.pubkey

FILENAME=`egrep 'Subject:.*CN=' server.pubkey | sed -e 's@.*CN=@@' -e 's@/.*@@' -e 's@\.@_@'`
cat server.privkey server.pubkey > $FILENAME.pem
mv server.privkey $FILENAME.prv
mv server.pubkey $FILENAME.pub

echo "Certificates is in: $TMPDIR"
