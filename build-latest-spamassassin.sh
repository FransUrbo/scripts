#!/bin/sh -e

DATE=`date +"%Y%m%d"`
DATE_822=`822-date`

if [ ! -f "Mail-SpamAssassin-3.0.0-cvs.tar.gz.$DATE" ]; then
    echo -n "Downloading archive: "
    wget http://spamassassin.apache.org/released/Mail-SpamAssassin-3.0.0-rc1.tar.bz2 2> /dev/null
    mv Mail-SpamAssassin-3.0.0-rc1.tar.bz2 Mail-SpamAssassin-3.0.0-cvs.tar.bz2.$DATE
    echo "done."
fi

if [ ! -d "Mail-SpamAssassin-3.0.0_$DATE" ]; then
    echo -n "Unpacking archive: "
    tar xjf Mail-SpamAssassin-3.0.0-cvs.tar.bz2.$DATE
    mv Mail-SpamAssassin-3.0.0 Mail-SpamAssassin-3.0.0_$DATE
    echo "done."
fi

echo -n "Preparing package: "
cd Mail-SpamAssassin-3.0.0_$DATE
REV=`rgrep -e 'EXTRA_VERSION.*$LastChangedRevision' . | grep -v strlen | sed -e 's@.*: @@' -e 's@ \$.*@@'`
mkdir ../spamassassin-3.0.0-r$REV ../spamassassin-3.0.0-r$REV.orig
find | cpio -p ../spamassassin-3.0.0-r$REV 2> /dev/null
find | cpio -p ../spamassassin-3.0.0-r$REV.orig 2> /dev/null
cd ../spamassassin-3.0.0-r$REV
cp -r ../.debian .
mv .debian debian
cat <<EOF > debian/changelog.new
spamassassin (3.0.0-r$REV-1) unstable; urgency=low

  * New upstream release - CVS version of new devel tree ($DATE).

 -- Turbo Fredriksson <turbo@debian.org>  $DATE_822

EOF
cat debian/changelog >> debian/changelog.new
mv debian/changelog.new debian/changelog
echo "done."

echo -n "Building package: "
debuild -uc -us -sa > ../spamassassin-3.0.0-r$REV.build 2>&1 
echo "done."

cd ..
DEB=`echo *$REV*.deb` ; CHANGES=`echo spamassassin_*$REV*.changes`

echo
echo "Directory: Mail-SpamAssassin-3.0.0_$DATE"
echo "Revision:  $REV"
echo "DEB pkgs:  $DEB"
