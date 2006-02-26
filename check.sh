#!/bin/sh

# $Id: check.sh,v 1.4 2006-02-26 09:54:51 turbo Exp $
TOT_ERR=

HOSTS="212.214.70.50 212.214.70.55 212.214.70.51"
DOMAINS="dagdrivarn.se bayour.com data-akut.se"

# --------------
for host in $HOSTS; do
    ERROR=0 ; x=1
    printf "Checking %10s: " $host

    # ---- PING
    echo -n "."
    ping -c 5 -n -q $host > /dev/null 2>&1
    [ "$?" != 0 ] && ERROR=`expr $ERROR + $x`
    x=`expr $x \* 2`

    # ---- NS pointers
    for domain in $DOMAINS; do
	echo -n "."
	host -s 5 -t ns $domain $host > /dev/null 2>&1
	[ "$?" != 0 ] && ERROR=`expr $ERROR + $x`

	x=`expr $x \* 2`
    done

    # ---- MX pointers
    for domain in $DOMAINS; do
	echo -n "."
	host -s 5 -t mx $domain $host > /dev/null 2>&1
	[ "$?" != 0 ] && ERROR=`expr $ERROR + $x`

	x=`expr $x \* 2`
    done

    # ---- LDAP
    echo -n "."
    ldapsearch -l 5 -x -h $host -LLL -b 'o=Bayour.COM,c=SE' ou=People \* OpenLDAPaci > /dev/null 2>&1
    [ "$?" != 0 ] && ERROR=`expr $ERROR + $x`
    x=`expr $x \* 2`

    # ---- SMTP
    echo -n "."
    /usr/local/sbin/test-tcp.pl $host 25
    [ "$?" != 0 ] && ERROR=`expr $ERROR + $x`
    x=`expr $x \* 2`

    # ---- AFS
    for server in ptserver vlserver; do
	echo -n "."
	bos status -localauth $host | egrep -q "$server.*disabled|$server.*shutdown"
	[ "$?" == 0 ] && ERROR=`expr $ERROR + $x`

	x=`expr $x \* 2`
    done

    # ---- HTTP
    echo -n "."
    lynx -connect_timeout=10 -head -dump http://$host 2>&1 | grep -q '^HTTP.*OK$'
    [ "$?" != 0 ] && ERROR=`expr $ERROR + $x`
    x=`expr $x \* 2`

    printf "=> %2d\n" $ERROR

    # ---- SPAMD
    echo -n "."
    /usr/local/sbin/test-tcp.pl $host 783
    [ "$?" != 0 ] && ERROR=`expr $ERROR + $x`
    x=`expr $x \* 2`

    # ---- Store this error
    if [ "$ERROR" != 0 ]; then
	if [ ! -z "$TOT_ERR" ]; then
	    TOT_ERR="$TOT_ERR $ERROR"
	else
	    TOT_ERR=$ERROR
	fi
    fi
done

# --------------
printf "Checking %10s: " imap
/usr/local/sbin/test-tcp.pl aurora 143
if [ "$?" != 0 ]; then
    echo "=> ERROR"
else
    echo "=> OK"
fi

# --------------
printf "Checking %10s: " provider
/usr/bin/ldapsearch -LLL -x -H ldapi://%2fvar%2frun%2fslapd%2fldapi.provider \
    -b 'o=Bayour.COM,c=SE' ou=People \* OpenLDAPaci > /dev/null 2>&1
if [ "$?" != 0 ]; then
    echo "=> ERROR"
else
    echo "=> OK"
fi

# --------------
if [ "$TOT_ERR" != "" ]; then
    echo ; echo "Explanations:"
    echo "     1: PING"
    echo "     2: NS dagdrivarn.se"
    echo "     4: NS bayour.com"
    echo "     8: NS data-akut.se"
    echo "    16: MX dagdrivarn.se"
    echo "    32: MX bayour.com"
    echo "    64: MX data-akut.se"
    echo "   128: LDAP search"
    echo "   256: SMTP"
    echo "   512: AFS/PTServer"
    echo "  1024: AFS/VLServer"
    echo "  2048: HTTP"
    echo "  4096: SPAMD"
fi
