#!/bin/sh

# $Id: df_afs.sh,v 1.2 2004-09-18 09:00:32 turbo Exp $

cd /

# --------------
# Set some default variables
AFSSERVER="aurora.bayour.com"
AFSCELL="bayour.com"

PARTS="`vos listpart ${AFSSERVER:-localhost} | sed 1d | head -n1`"
for part in $PARTS; do
    vos partinfo ${AFSSERVER:-localhost} $part
done
