#!/bin/sh

# We don't care what we get, just that we can connect
# to the LDAP server... Hence, anonymous bind (which
# don't have access to anything).
ldapsearch -x -LLL -H ldapi://%2fvar%2flib%2fnamed%2fvar%2frun%2fldapi \
    -b ou=DNS,o=Bayour.COM,c=SE relativeDomainName=aurora \
    > /dev/null 2>&1
code=$?

if [ "$code" != 0 ]; then
    /etc/init.d/slapd.bind9 start
fi
