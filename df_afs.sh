#!/bin/sh

# $Id: df_afs.sh,v 1.1 2003-01-31 06:45:21 turbo Exp $

cd /

# --------------
# Set some default variables
AFSSERVER="papadoc.bayour.com"
AFSCELL="bayour.com"

PARTS="`vos listpart ${AFSSERVER:-localhost} | sed 1d | head -n1`"
for part in $PARTS; do
    vos partinfo ${AFSSERVER:-localhost} $part
done
