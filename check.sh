#!/bin/sh

# $Id: check.sh,v 1.2 2006-01-02 22:21:12 turbo Exp $

TOT_ERR=0
HOSTS="aurora localhost fritz 51pegasi"
for host in $HOSTS; do
    ERROR=0
    printf "Checking %10s: " $host

    host -t ns dagdrivarn.se $host > /dev/null 2>&1
    [ "$?" != 0 ] && ERROR=1

    host aurora $host > /dev/null 2>&1
    [ "$?" != 0 ] && ERROR=`expr $ERROR + 2`

    host -t mx data-akut.se $host > /dev/null 2>&1
    [ "$?" != 0 ] && ERROR=`expr $ERROR + 4`

    ldapsearch -x -h $host -LLL -b 'o=Bayour.COM,c=SE' ou=People \* OpenLDAPaci > /dev/null 2>&1
    [ "$?" != 0 ] && ERROR=`expr $ERROR + 8`

    printf "=> %2d\n" $ERROR

    TOT_ERR=`expr $TOT_ERR + $ERROR`
done

printf "Checking %10s: " provider
/usr/bin/ldapsearch -LLL -x -H ldapi://%2fvar%2frun%2fslapd%2fldapi.provider \
    -b 'o=Bayour.COM,c=SE' ou=People \* OpenLDAPaci > /dev/null 2>&1
[ "$?" != 0 ] && ERROR=`expr $ERROR + 16`
printf "=> %2d\n" $ERROR

if [ "$TOT_ERR" != 0 ]; then
    echo
    echo "Explanations:"
    echo "  1: NS dagdrivarn.se"
    echo "  2: A/CNAME Aurora"
    echo "  4: MX data-akut.se"
    echo "  8: ldapsearch"
    echo " 16: ldap provider"
fi
