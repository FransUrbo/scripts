#!/bin/sh

# $Id: create_mailinglist.sh,v 1.2 2005-10-29 09:39:16 turbo Exp $

# -a Archived
# -d Digest
# -f Prefix
# -g Guard archive
# -i Indexed for WWW archive access
# -k Kill
# -l List subscribers
# -m Message  moderation
# -n New text file
# -o Others rejected
# -q ReQuest address is serviced
# -r Remote  admin
# -t Trailer
OPTIONS=-adfgiklmnoqrt

if [ -z "$1" ]; then
    echo "usage: `basename $0` [list(s)]"
    exit 1
else
    LISTS="$*"
fi

for list in $LISTS; do
        ezmlm-make $OPTIONS /var/lists/$list ~alias/.qmail-$list $list bayour.com
        ezmlm-sub /var/lists/$list/mod   turbo@bayour.com
        ezmlm-sub /var/lists/$list/allow turbo@bayour.com
        ezmlm-sub /var/lists/$list       turbo@bayour.com

        (cd ~alias && chown alias.qmail .qmail-$list*)
        (cd /var/lists && chown alias.www-data $list)

        find /var/lists/$list -type d -exec chmod 755 {} \;
        find /var/lists/$list -type f -exec chmod 644 {} \;
done
