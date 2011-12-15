#!/bin/bash

CVSROOT=/var/lib/cvs

mkdir -p /tmp/cvs2git && cd /tmp/cvs2git || exit 1
#git config --global user.name "Turbo Fredriksson"
#git config --global user.email turbo@bayour.com

# !! NOT Git'ed !!
# cablelogin/                            mkhome/        sockets/         turbo/
# CVSROOT/                               mp3d/          test/                 
# CVSROOT-FreeBSD/  linux4amigaone.old/  PnP-Dists/                             
# debian/           linux4amigaone/      emacs/         SSL-Certs/              

# Successfully Git'ed
# bind9-ldap php-modules mod_ldap_cfg:libapache-mod-ldapcfg 
# scripts snmp-modules tcpquota VBox dnssec-tools firewall 
# xadmin xezmlm LastBerakning LastSakring 

for module in  SMSAlarmServer phpQLAdmin
do
  TMPFILE=`tempfile -d /tmp`

  if echo $module | grep -q ':'; then
      set -- `echo $module | sed 's@:@ @'`
      module=$1
      git=$2
  else
      git=$module
  fi

  # Do the conversion
  (cvs2git --blobfile=$TMPFILE-blob.dat \
      --dumpfile=$TMPFILE-dump.dat \
      --username=turbo \
      --retain-conflicting-attic-files \
      --fallback-encoding=latin_1 \
      /var/lib/cvs/$module

  # Initialize a git repository
  mkdir $module
  pushd $module
    git init

    # Load the dump files into the new git repository using git fast-import:
    cat $TMPFILE-blob.dat $TMPFILE-dump.dat | \
	git fast-import

    # Push all tags and branches to github
    if git remote show | grep -q ^origin; then
	git remote rm origin
    fi
    git remote add origin git@github.com:FransUrbo/$git.git
    git push --mirror origin
  popd

  # Checkout the new git repo
  pushd ~/src/GITs
    git clone git@github.com:FransUrbo/$git.git
  popd) 2>&1 | tee $module.log

  rm -f $TMPFILE*
done
