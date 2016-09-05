#!/bin/bash

# $Id: create_cert.sh,v 1.4 2005/06/16 05:45:15 turbo Exp $

BASE_DIR=/etc/ssl
BASE_CFG=openssl.cnf

# How many aliases to support
max=10

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

    if [ "$tmp" != '' ]; then
	eval `echo $var2=$tmp` # alias$cnt=$tmp
	eval `echo $var1=$tmp` # ALIAS_NAME$cnt=$tmp

	export `echo $var1`    # export ALIAS_NAME$cnt

	cnt=`expr $cnt + 1`
    else
	# No alias - Make sure we break out
	break
    fi
done
cnt=`expr $cnt - 1`

# Possibly use an existing request
read -p "Certificate request file: " -t 10 cert_req_file

# Create a temporary directory
TMPDIR=`tempfile`
rm -f $TMPDIR
mkdir $TMPDIR
cd $TMPDIR

# Create the temporary config file
cfg="$TMPDIR/$BASE_CFG"
if [ $cnt -ge 1 ]; then
    i=1
    while [ $i -le $cnt ]; do
	printf >> $cfg "DNSNAME%-2d                       = \$ENV::ALIAS_NAME$i\n" $i
	i=`expr $i + 1`
    done

    printf >> $cfg "RANDFILE                        = \$ENV::HOME/.rnd\n"
    printf >> $cfg "\n[ alternative_names ]\n"

    i=1
    while [ $i -le $cnt ]; do
	printf >> $cfg "DNS.%-2d                          = \$DNSNAME$i\n" $i

	i=`expr $i + 1`
    done

    printf >> $cfg "\n"
    cat $BASE_DIR/$BASE_CFG | sed 's@#subjectAltName@subjectAltName@' >> $cfg
else
    printf > $cfg "RANDFILE                        = \$ENV::HOME/.rnd\n"
    cat $BASE_DIR/$BASE_CFG >> $cfg
fi
cfg="-config $cfg"

# ---------------------------

# -newkey arg
#   this option creates a new certificate request and a new private key. The argument takes one of two forms. rsa:nbits, where nbits is the number
#   of bits, generates an RSA key nbits in size. dsa:filename generates a DSA key using the parameters in the file filename.

if [ -z "${cert_req_file}" -o ! -f "${cert_req_file}" ]; then
    # Skapa cert req (five year)
    openssl req $cfg -nodes -new -days 1825 -out server_req.pubkey -keyout server.privkey
else
    cp "${cert_req_file}" server_req.pubkey
fi

# Signera cert requesten med CA certet
openssl ca $cfg -in server_req.pubkey -out server.pubkey

if [ -f "server.pubkey" ]; then
    rm server_req.pubkey
    [ -f "${cert_req_file}" ] || \
	chmod 644 server.privkey server.pubkey
    
    FILENAME=`egrep 'Subject:.*CN=' server.pubkey | sed -e 's@.*CN=@@' -e 's@/.*@@' -e 's@\.@_@g' -e 's@ @_@g'`
    if [ ! -z "$FILENAME" ]; then
	if [ ! -f "${cert_req_file}" ]; then
	    cat server.pubkey server.privkey > $FILENAME.pem
	    mv server.privkey $FILENAME.prv
	fi
	mv server.pubkey $FILENAME.pub
	chmod 600 $FILENAME.prv $FILENAME.pub $FILENAME.pem

	echo "Converting private key to something GnuTLS understands:"
	certtool -k < $FILENAME.prv > $FILENAME.prv-gnutls

	echo "Moving files to cert database directory:"
	[ ! -d "$BASE_DIR/certs/" ] && mkdir -p $BASE_DIR/certs
	cp -v $FILENAME.pem $FILENAME.prv $FILENAME.prv-gnutls $FILENAME.pub $BASE_DIR/certs/
	if [ "$?" = "0" ]; then
	    cd /
	    rm -Rf $TMPDIR
	fi

	read -p "Create personal P12 certificate [y/N]? " -t 10 tmp
	if echo $tmp | grep -i '^y'; then
	    openssl pkcs12 -export \
		-in       $BASE_DIR/certs/$FILENAME.pem \
		-inkey    $BASE_DIR/certs/$FILENAME.prv \
		-out      $BASE_DIR/certs/$FILENAME.p12 \
		-certfile $BASE_DIR/CA/cacert.pem
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
