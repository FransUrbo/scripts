#!/bin/sh

TMPFILE=`tempfile -p user.`
ADMIN_PRINCIPAL="turbo@BAYOUR.COM"
MASTER_KERBEROS_SERVER="kerberos1.bayour.com"
MASTER_LDAP_SERVER="-H ldaps://ldap1.bayour.com"

# If unset, don't use AFS...
AFS_CELL="bayour.com"
AFS_SERVER="papadoc.bayour.com"
AFS_QUOTA="5000"

KRB5_RSH_CMD="krb5-rsh -x -l root $MASTER_KERBEROS_SERVER /usr/sbin/kadmin.local"

cd /

#############################################
# Get next availible UID number
get_uidnumber () {
    echo -n "Looking for next free UserID Number: "
    UIDNR=`ldapsearch $MASTER_LDAP_SERVER -LLL '(&(uidnumber=*)(objectclass=posixAccount))' \
	uidnumber 2> /dev/null | grep -i '^uidNumber: 10' | \
	sort | tail -n1 | sed 's@uidNumber: @@'`

    if [ -z "$UIDNR" ]; then
	echo "Could not get a UIDNumber!"
	echo "UIDNR: $UIDNR"
	exit 1
    fi
    UIDNR=`expr $UIDNR + 1`
    GIDNR=$UIDNR
    echo "$UIDNR"
}

#############################################
# Find out what to do
#	Add, remove user
#	Add, remove service key
if echo "$1" | egrep -qi "\-del|\-rem"; then
    DELETE=1 ; set -- `echo $*` ; shift

    if [ -z "$1" ]; then
	echo "Usage: `basename $0` uid"
    fi

    USERID="$1"
#elsif echo "$1" | egrep -qi "\-host"; then
#    # TODO: Add a host/fqdn service principal to KDC
else
    if [ -z "$1" -o -z "$2" -o -z "$3" -o -z "$4" ]; then
	echo "Usage: `basename $0` uid firstname lastname passwd"
	exit 1
    fi

    USERID="$1"
    FIRSTNAME="$2"
    LASTNAME="$3"
    PASSWD="$4"
fi

#############################################
# Verify delete/add
if [ -z "$DELETE" ]; then
    # Add a user to the database(s)
    get_uidnumber

    cat /etc/adduser.ldif | sed \
	-e "s@%UID%@$USERID@g" \
	-e "s@%UIDNUMBER%@$UIDNR@g" \
	-e "s@%GIDNUMBER%@$GIDNR@g" \
	-e "s@%FIRSTNAME%@$2@g" \
	-e "s@%LASTNAME%@$3@g" \
	-e "s@%CLEARTEXTPW%@$PASSWD@g" \
	> $TMPFILE
	
    echo -n "Verify LDIF [y/N]? "
    read RESULT
    if echo $RESULT | grep -iq "^y"; then
	less $TMPFILE
    fi

    echo -n "Add this user to the database(s) [y/N]? "
    read RESULT
else
    # Find user dn
    DN=`ldapsearch -LLL $MASTER_LDAP_SERVER "(&(uid=$USERID)(objectclass=posixAccount))" 2> /dev/null | grep ^dn: | sed 's@dn: @@'`

    if [ ! -z "$DN" ]; then
	echo "User DN: $DN"
	echo -n "Delete this user from the database(s) [y/N]? "
	read RESULT
    else
	echo "No such user in LDAP database..."
	exit 1
    fi
fi

#############################################
# Do the magic
if echo $RESULT | grep -iq "^y"; then
    if [ -z "$DELETE" ]; then
	echo -n "Adding user '$USERID' to: "
    else
	echo -n "Deleting user '$USERID' from: "
    fi

    # -------------------------------------------
    # LDAP
    if [ -z "$DELETE" ]; then
	# Add user to LDAP database...
	RESULT=`cat $TMPFILE | ldapadd $MASTER_LDAP_SERVER -U $ADMIN_PRINCIPAL 2>&1`
	if echo "$RESULT" | grep -q "^adding new entry"; then
	    echo -n "LDAP "
	else
	    echo "->LDAPERROR<-"
	    exit 3
	fi
    else
	# Save the homedirectory for AFS delete...
	AFS_DIR=`ldapsearch -LLL $MASTER_LDAP_SERVER "(&(uid=$USERID)(objectclass=posixAccount))" 2> /dev/null | grep -i ^homedirectory: | sed 's@homeDirectory: @@i'`

	ldapdelete $MASTER_LDAP_SERVER -U $ADMIN_PRINCIPAL "$DN" > /dev/null 2>&1
	ldapdelete $MASTER_LDAP_SERVER -U $ADMIN_PRINCIPAL "nsLIProfileName=$USERID,$DN" > /dev/null 2>&1
	echo -n "LDAP "
    fi

    # -------------------------------------------
    # KERBEROS
    if [ -z "$DELETE" ]; then
	# Add user to KerberosV database...

	RESULT=`$KRB5_RSH_CMD -q \"ank -pw $PASSWD $USERID\" 2>&1`
	if echo "$RESULT" | grep -qi "already exists"; then
	    # Principal already exists, change password...
	    RESULT=`$KRB5_RSH_CMD -q \"cpw -pw $PASSWD $USERID\" 2> /dev/null`
	    echo -n "CPW "
	elif echo "$RESULT" | grep -qi "Principal \"$USERID@BAYOUR.COM\" created"; then
	    # Principal successfully created.
	    echo -n "KDC "
	fi
    else
	# Delete the user from KerberosV database...
	RESULT=`$KRB5_RSH_CMD -q \"delprinc -force $USERID\" 2>&1`
	echo -n "KDC "
    fi

    # -------------------------------------------
    # AFS (see chapter 13 of the IBM administration guide)
    if [ -z "$DELETE" -a ! -z "$AFS_CELL" -a ! -z "$AFS_SERVER" ]; then
	# Add user to AFS database...

	HOME_DIR=`cat $TMPFILE | grep -i ^homeDirectory | sed 's@homeDirectory: @@i'`
	AFS_DIR="`echo $HOME_DIR | sed 's@/afs/@/afs/\.@'`"

	if [ ! -d "$AFS_DIR" -a ! -d "$HOME_DIR" ]; then
	    if ! pts listentries | grep -q ^$USERID; then
		# Create the user
		pts createuser $USERID $UIDNR > /dev/null
		echo -n "A"
	    fi

	    # Create the volume
	    vos create -server $AFS_SERVER -partition /vicepd \
		-name user.$USERID -maxquota ${AFS_QUOTA:-5000} \
		> /dev/null
	    echo -n "F"

	    # Create the mountpoint
	    fs mkm $AFS_DIR user.$USERID ; chmod 755 $AFS_DIR

	    # Copy the SKEL to the homedirectory
	    if [ -d /etc/skel ]; then
		cd /etc/skel && find | cpio -p $AFS_DIR > /dev/null 2>&1
		chown -R $UIDNR.$UIDNR $AFS_DIR > /dev/null
	    fi

	    # Set the ACL's on the volume
	    fs setacl $AFS_DIR $USERID all system:administrators all webserver rl system:anyuser none -clear
	    fs setacl $AFS_DIR/.html $USERID all system:administrators all webserver rl system:anyuser rl -clear
	    echo -n "S"
	fi
    else
	# Unmount the users homedirectory before we destroy it!
	if fs lsm $AFS_DIR 2> /dev/null | grep -q "is a mount point for volume '#user.$USERID'"; then
	    fs rmm $AFS_DIR
	    echo -n "A"
	fi

	# Remove volume
	if vos listvol papadoc | grep -q '^user.$USERID '; then
	    vos remove -id user.$USERID > /dev/null
	    echo -n "F"
	fi

	# Delete entry from protection database
	if pts listentries | grep -q ^$USERID; then
	    pts delete $USERID > /dev/null 2>&1 
	    echo -n "S"
	fi
    fi

    vos release user > /dev/null 2>&1		# Release the user volume
    vos release root.cell > /dev/null 2>&1	# Release the AFS root volume
    echo

    # -------------------------------------------
    # MAILDIR
#    if [ -z "$DELETE" ]; then
	MAIL_DIR=`cat $TMPFILE | grep -i ^mailMessageStore | sed 's@mailMessageStore: @@i'`
	sudo maildirmake $MAIL_DIR $USERID
#    else
#    fi
fi
rm -f $TMPFILE

