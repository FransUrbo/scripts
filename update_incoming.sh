#!/bin/sh

for arch in all i386; do
    cd /pub/debian/dists/debian-installer/binary-$arch || exit 1
    mv -iv `find /var/incoming/*_$arch.*deb | sed -e 's@_.*@_*deb@' -e 's@/var/incoming/@@'` ../../../old/

    cd /var/incoming || exit 1
    mv -iv `find *_$arch.*deb | sed 's@_.*@_*deb@'` /pub/debian/dists/debian-installer/binary-$arch/
done
mv *.changes /pub/debian/dists/debian-installer/source

cd /home/ftp
bin/update_packages.sh debian-installer
