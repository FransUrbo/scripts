#!/bin/sh

TOPDIR=/home/ftp/pub
BASEDIR=$TOPDIR/debian/dists
SCANPKG=$TOPDIR/../bin/dpkg-scanpackages

# ----------- DON'T CHANGE ANYTHING BELOW -----------
# ---------------------------------------------------

TMPFILE=`tempfile`
if [ -z "$1" ]; then
    DIRS=`find $BASEDIR/ -name '[a-z]*' -maxdepth 1 | sort`
    DIRS=`echo $DIRS`
else
    if [ ! -z "$2" ]; then
	for dist in $*; do
	    DIRS="$DIRS $BASEDIR/$dist"
	done
    else
	DIRS="$BASEDIR/$1"
    fi
fi

for dir in $DIRS; do
    dist=`basename $dir`
    cd $TOPDIR || (echo "can't change to top directory!" ; exit 1)
    echo "$dir"

    ARCHS=`find $dir -type d -name 'binary-*' -maxdepth 1 -exec basename {} \; | grep -v binary-all | sort`

    # --------------------------
    # Create overrides file(s)
    printf "  Updating override files in arch: "
    for arch in binary-all $ARCHS; do
	echo -n "$arch "
	echo -n > $dir/.override_$arch

	for pkg in `find $dir/$arch -type f -name '*.deb' | sed -e "s@$dir/$arch/@@" | sed -e 's@_[0-9].*@@' | sort`; do
	    set -- `echo $pkg | sed 's@/@ @'`
	    printf "%-55s optional %s\n" $2 $1 >> $dir/.override_$arch
	done
    done
    echo

    # --------------------------
    # Create Links to binary-all
    printf "  Creating symlinks in arch:       "
    find $dir -type l -exec rm {} \;
    for arch in $ARCHS; do
	echo -n "$arch "

	for pkg in `find $dir/binary-all -type f -name '*.deb' | sed 's@\./@@'`; do
	    tmp=`dirname $pkg`
	    pkg_dir=`basename $tmp | sed 's@binary-all@@'`
	    pkg_file=`basename $pkg`

	    if [ ! -h "$dir/$arch/$pkg_dir/$pkg_file" -a \
		 ! -f "$dir/$arch/$pkg_dir/$pkg_file" ]
	    then
		ln -s ../../binary-all/$pkg_dir/$pkg_file $dir/$arch/$pkg_dir/$pkg_file
	    fi
	done

	ln -s ../Release $dir/$arch/Release
    done
    echo

    # --------------------------
    # Create Packages files
    printf "  Creating packages file in arch:  "
    for arch in $ARCHS source; do
	# Setup a override from ALL+ARCH
	if [ -f "$dir/.override_binary-all" -a -f "$dir/.override_$arch" ]; then
	    cat $dir/.override_binary-all $dir/.override_$arch | sort > $TMPFILE
	fi

	if [ -d "$dir/$arch" ]; then
	    echo -n "$arch"

	    if echo $arch | grep -q binary; then
		# Binary packages

		$SCANPKG    $dir/$arch $TMPFILE ../ 2> /dev/null | sed "s@$TOPDIR/@@" >  $dir/$arch/Packages
		$SCANPKG -u $dir/$arch $TMPFILE ../ 2> /dev/null | sed "s@$TOPDIR/@@" >> $dir/$arch/Packages
		gzip -9c $dir/$arch/Packages > $dir/$arch/Packages.gz

		packages=`cat $dir/$arch/Packages | grep ^Package: | wc -l`
	    else
		# Source packages
		# Wrote 272 entries to output Packages file.

		dpkg-scansources $dir/$arch $TMPFILE ../ 2> /dev/null | sed "s@$TOPDIR/@@" > $dir/$arch/Sources
		gzip -9c $dir/$arch/Sources > $dir/$arch/Sources.gz

		packages=`cat $dir/$arch/Sources | grep ^Package: | wc -l`
	    fi

	    packages=`echo $packages | sed 's@\ @@g'`
	    echo -n "/$packages "
	fi
    done
    echo

    # --------------------------
    # Create the Release file
    printf "  Creating release file in topdir: "
    PKGFILES=`find $dir -name 'Package*' -type f`
    if [ -f "$dir/.release" ]; then
	cat $dir/.release | sed "s@%DATE1%@`822-date`@" > $dir/Release 
    else
	echo `822-date` > $dir/Release
    fi

    echo "MD5Sum:" >> $dir/Release
    for pkgfile in $PKGFILES; do
	file=`echo $pkgfile | sed "s@$BASEDIR/$dist/@@"`

	set -- `/bin/ls -l $pkgfile`
	size=$5

	md5sum=`md5sum $pkgfile | sed 's@\ .*@@'`

	printf " $md5sum %17d main/$file\n" $size >> $dir/Release
    done
    echo -n "md5 "

    echo "SHA1:" >> $dir/Release
    for pkgfile in $PKGFILES; do
	file=`echo $pkgfile | sed "s@$BASEDIR/$dist/@@"`

	set -- `/bin/ls -l $pkgfile`
	size=$5

	sha1=`openssl dgst -sha1 $pkgfile | sed 's@.*\ @@'`

	printf " $sha1 %17d main/$file\n" $size >> $dir/Release
    done
    echo "sha1"

    DISKS=`find $dir -type d -name 'disks-*' -maxdepth 1 -exec basename {} \; | sort`

    # --------------------------
    # Create the 'main' link
    printf "  Updating current link in disk:   "
    for disk in $DISKS; do
	echo -n "$disk "
	(cd $dir/$disk && ln -s . current)
    done
    echo
    if [ ! -f "$dir/main" -a \
	 ! -h "$dir/main" ]
    then
	(cd $dir && ln -s . main)
    fi
done

rm -f $TMPFILE
