#!/bin/sh

# $Id: check.sh,v 1.7 2006-06-21 10:35:46 turbo Exp $
TOT_ERR=

#HOSTS="212.214.70.50 212.214.70.55 212.214.70.51"
HOSTS="212.214.70.50 212.214.70.51"
DOMAINS="dagdrivarn.se bayour.com data-akut.se"

# --------------
for host in $HOSTS; do
    ERROR=0
    printf "Checking %10s: " $host

    # ---- PING
    echo -n "."
    ping -c 5 -n -q $host > /dev/null 2>&1
    if [ "$?" = 0 ]; then
	# ---- NS pointers
	for domain in $DOMAINS; do
	    echo -n "."
	    host -s 5 -t ns $domain $host > /dev/null 2>&1
	    [ "$?" != 0 ] && ERROR="ns/$domain;"
	done
	
	# ---- MX pointers
	for domain in $DOMAINS; do
	    echo -n "."
	    host -s 5 -t mx $domain $host > /dev/null 2>&1
	    [ "$?" != 0 ] && ERROR="mx/$domain;"
	done
	
	# ---- LDAP
	echo -n "."
	ldapsearch -l 10 -x -h $host -LLL -b 'o=Bayour.COM,c=SE' -s one ou=People \* OpenLDAPaci > /dev/null 2>&1
	[ "$?" != 0 ] && ERROR="ldapsearch;"
	
	# ---- SMTP
	echo -n "."
	/usr/local/sbin/test-tcp.pl $host 25
	[ "$?" != 0 ] && ERROR="smtp;"
	
	# ---- AFS
	for server in ptserver vlserver; do
	    echo -n "."
	    bos status -localauth $host | egrep -q "$server.*disabled|$server.*shutdown"
	    [ "$?" == 0 ] && ERROR="afs/$server;"
	done
	
	# ---- HTTP
	echo -n "."
	lynx -connect_timeout=10 -head -dump http://$host 2>&1 | grep -q '^HTTP.*OK$'
	[ "$?" != 0 ] && ERROR="http;"
	
	# ---- SPAMD
	echo -n "."
	/usr/local/sbin/test-tcp.pl $host 783
	[ "$?" != 0 ] && ERROR="spamd;"
    else
	ERROR="ping;"
    fi


    # ---------------------
    # ---- Store this error
    printf "=> %s\n" $ERROR
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
