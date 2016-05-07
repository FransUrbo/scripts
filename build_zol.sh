#!/bin/sh

# For debugging
#GIT_APP_REPO="git@github.com:zfsonlinux/pkg-${APP}.git"
GIT_APP_REPO="git@github.com:fransurbo/pkg-${APP}.git"

# No checking for correct, missing or faulty values will be done in this
# script. This is the second part of a automated build process and is intended
# to run inside a Docker container. See comments in 'setup_and_build.sh' for
# more information.
#
# Copyright 2016 Turbo Fredriksson <turbo@bayour.com>.
# Released under GPL, version of your choosing.

set -x
set -e

echo "=> Building (${APP}/${DIST}/${BRANCH})"


# --------------------------------
# --> C O D E  C H E C K O U T <--
# --------------------------------

# Checking out the code.
git clone --origin pkg-${APP} ${GIT_APP_REPO}
cd pkg-${APP}

# Add remote ${APP}.
git remote add ${APP} git@github.com:zfsonlinux/${APP}.git
git fetch ${APP}

# Setup user for commits.
git config --global user.name "${GITNAME}"
git config --global user.email "${GITEMAIL}"

# ----------------------------------
# --> C O D E  D I S C O V E R Y <--
# ----------------------------------

# 1. Checkout the correct branch.
if ! git show pkg-${APP}/${BRANCH}/debian/${DIST} > /dev/null 2>&1; then
    # Branch don't exist - use 'jessie/master', because that's currently
    # the latest.
    git checkout -b ${BRANCH}/debian/sid pkg-${APP}/master/debian/jessie
else
    if [ "${BRANCH}" = "snapshot" ]; then
	# TODO: !! Temporary solution !!
	# Because snapshot is very behind my released versions, use the
	# 'master' branch instead.

	# 1. Checkout master repository into a new snapshot branch
	#    NOTE: This will need to be force pushed at the end.
	git checkout -b ${BRANCH}/debian/${DIST} ${APP}/master

	# 2. Get the debian directory from the master branch.
	git checkout pkg-${APP}/master/debian/${DIST} -- debian

	if [ "${APP}" = "xxx" ]; then
	    # TODO: The ZFS patches needs to be updated
	    # 3. Update debian patches.
	    for patch in 0002-Prevent-manual-builds-in-the-DKMS-source.patch \
			     PR1099.patch PR1476.patch PR3465.patch \
			     libzfs-dependencies
	    do
		curl http://bayour.com/misc/${patch} \
		     > debian/patches/${patch} 2> /dev/null
		git add debian/patches/${patch}
	    done

	    # Needs to be ported, so in the mean time disable them.
	    for patch in PR1867 PR2668 PR3559 PR3560 PR3884; do 
		cat debian/patches/series | grep -v "${patch}"  > x
		mv x debian/patches/series
		git add debian/patches/series
	    done

	    # Update the packaging
	    curl http://bayour.com/misc/build-deps.patch | \
		patch -p1
	    git add debian/control.in
	fi

	# 3. Commit changes.
	msg="Start out with ${APP}/master then get debian dir from "
	msg="${msg} pkg-${APP}/master/debian/${DIST} (w/ updated patches)"
	git commit -m "$msg"
    else
	git checkout ${BRANCH}/debian/${DIST}
    fi
fi

# Check which branch to use for version check
if [ "${BRANCH}" = "snapshot" ]; then
    branch="${APP}/master"
else
    branch="$(git tag -l ${APP}-[0-9]* | tail -n1)"
fi

# Make sure that the code in the branch have changed.
sha="$(git log --pretty=oneline --abbrev-commit ${branch} | \
    head -n1 | sed 's@ .*@@')"
if [ -f "${WORKSPACE}/../lastSuccessfulSha-${APP}-${DIST}-${BRANCH}" ]; then
    old="$(cat "${WORKSPACE}/../lastSuccessfulSha-${APP}-${DIST}-${BRANCH}")"
    if [ "${sha}" = "${old}" ]; then
        echo "=> No point in building - same as previous version."
        exit 0
    fi
fi

# 2. Get the latest upstream tag.
#    If there's no changes, exit successfully here.
if [ "${BRANCH}" != "snapshot" ]; then
    # TODO: !! Temporary solution !!
    # No need to do this, we're already using the master branch.
    git merge -Xtheirs --no-edit ${branch} 2>&1 | \
	grep -q "^Already up-to-date.$" && \
	no_change=1
    if [ "${no_change}" = "1" -a "${DIST}" != "sid" ]; then
        echo "=> No point in building - same as previous version."
	exit 0
    fi
fi

# Get the version
pkg_version="$(git describe ${branch} | sed "s@^${APP}-@@")-1-${DIST}"
[ "${BRANCH}" = "snapshot" ] && pkg_version="${pkg_version}-daily"

# ----------------------------------
# --> P A C K A G E  U P D A T E <--
# ----------------------------------

# Update the GBP config file
sed -i -e "s,^\(debian-branch\)=.*,\1=${BRANCH}/debian/${DIST}," \
       -e "s,^\(debian-tag\)=.*\(/\%.*\),\1=${BRANCH}/debian/${DIST}\2," \
       -e "s,^\(upstream-.*\)=.*,\1=${branch},"  debian/gbp.conf

# Update and commit
echo "=> Update and commit the changelog"
if [ "${BRANCH}" = "snapshot" ]; then
    dist="${DIST}-daily"
    msg="daily"

    # Dirty hack, but it's the fastest, easiest way to solve
    #   E: spl-linux changes: bad-distribution-in-changes-file sid-daily
    # Don't know why I don't get that for '{wheezy,jessie}-daily as well,
    # but we do this for all of them, just to make sure.
    mkdir -p /usr/share/lintian/vendors/debian/main/data/changes-file
    if [ ! -f "/usr/share/lintian/vendors/debian/main/data/changes-file/known-dists" ]
    then
	echo "${dist}" >  /usr/share/lintian/vendors/debian/main/data/changes-file/known-dists
    else
	echo "${dist}" >> /usr/share/lintian/vendors/debian/main/data/changes-file/known-dists
    fi
else
    dist="${DIST}"
    msg="upstream"
fi
debchange --distribution "${dist}" --newversion "${pkg_version}" \
	  --force-bad-version --force-distribution \
	  --maintmaint "New $msg release - ${sha}."

git add debian/changelog debian/gbp.conf
git commit -m "New daily release - $(date -R)/${sha}."

# -----------------------------------
# --> S T A R T  T H E  B U I L D <--
# -----------------------------------

# Setup debian directory.
echo "=> Start with a clean debian/controls file"
debian/rules override_dh_prep-base-deb-files

# Install dependencies
deps="$(dpkg-checkbuilddeps 2>&1 | \
    sed -e 's,.*dependencies: ,,' -e 's, (.*,,')"
while [ -n "${deps}" ]; do
    echo "=> Installing package dependencies"
    apt-get install -y ${deps} > /dev/null 2>&1
    if [ "$?" = "0" ]; then
	deps="$(dpkg-checkbuilddeps 2>&1 | \
	    sed -e 's,.*dependencies: ,,' -e 's, (.*,,')"
    else
	echo "   ERROR: install failed"
	exit 1
    fi
done

# Build packages
echo "=> Build the packages"
type git-buildpackage > /dev/null 2>&1 && \
    gbp="git-buildpackage" || gbp="gbp buildpackage"

${gbp} --git-ignore-branch --git-keyid="${GPKGKEYID}" --git-tag \
       --git-ignore-new --git-builder="debuild -i -I -k${GPGKEYID}" 

# ------------------------
# --> F I N I S H  U P <--
# ------------------------

# Upload packages
echo "=> Upload packages"
dupload ${WORKSPACE}/*.changes

# Push our changes to GitHub
if [ "${BRANCH}" = "snapshot" ]; then
    # TODO: !! Temporary solution !!
    force="--force"
fi
# TODO: !! NOT YET !!
#git push --all ${force}

# Record changes
echo "=> Recording successful build (${sha})"
echo "${sha}" > "${WORKSPACE%%/workspace*}/lastSuccessfulSha-${DIST}-${APP}"
