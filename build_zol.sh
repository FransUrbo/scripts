#!/bin/sh

# Path to repository with packaging.
GIT_APP_REPO="git@github.com:fransurbo/pkg-${APP}.git"

# No checking for correct, missing or faulty values will be done in this
# script. This is the second part of a automated build process and is
# intended to run inside a Docker container. See comments in
# 'setup_and_build.sh' for more information.
#
# The use of 'master' and 'snapshot' (the two options) doesn't refer to the
# master branch, but the base of the pkg-{spl,zfs} branch trees in the
# pkg-{spl,zfs} repositories. The 'master' tree is the released versions
# and 'snapshot' are the dailies.
#
# Copyright 2016 Turbo Fredriksson <turbo@bayour.com>.
# Released under GPL, version of your choosing.

set -x
set -e

echo "=> Building (${APP}/${DIST}/${BRANCH})"

# If we haven't mounted the $HOME/.ssh directory into the Docker container,
# the known_hosts don't exit. However, if we have a local copy (in the
# scratch dir), then use that.
# To avoid a 'Do you really want to connect' question, make sure that the
# hosts we're using is all in there.
if [ ! -f "/root/.ssh/known_hosts" -a "/tmp/docker_scratch/known_hosts" ]
then
    # We probably don't have the .ssh directory either, so create it.
    [ -d "/root/.ssh" ] || mkdir -p /root/.ssh
    cp /tmp/docker_scratch/known_hosts /root/.ssh/known_hosts
fi

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
    # Branch don't exist (probably 'sid') - use the 'jessie' branch, because
    # that's currently the latest.
    # If the system is very different from this, the build will probably
    # fail, but it's a start.
    git checkout -b ${BRANCH}/debian/sid pkg-${APP}/${BRANCH}/debian/jessie
else
    # Not a snapshot - get the correct branch.
    git checkout ${BRANCH}/debian/${DIST}
fi

# 2. Check which branch to use for version check and to get 'latest' from.
if [ "${BRANCH}" = "snapshot" ]; then
    branch="${APP}/master"
else
    branch="$(git tag -l ${APP}-[0-9]* | tail -n1)"
fi

# 3. Make sure that the code in the branch have changed.
sha="$(git log --pretty=oneline --abbrev-commit ${branch} | \
    head -n1 | sed 's@ .*@@')"
if [ -f "/tmp/docker_scratch/lastSuccessfulSha-${APP}-${DIST}-${BRANCH}" ]
then
    old="$(cat "/tmp/docker_scratch/lastSuccessfulSha-${APP}-${DIST}-${BRANCH}")"
    if [ "${sha}" = "${old}" ]; then
        echo "=> No point in building - same as previous version."
        exit 0
    fi
fi

# 4. Get the latest upstream tag.
#    If there's no changes, exit successfully here.
git merge -Xtheirs --no-edit ${branch} 2>&1 | \
    grep -q "^Already up-to-date.$" && \
    no_change=1
if [ "${no_change}" = "1" -a "${DIST}" != "sid" ]; then
    echo "=> No point in building - same as previous version."
    exit 0
fi

# 5. Get the version
pkg_version="$(git describe ${branch} | sed "s@^${APP}-@@")-1-${DIST}"
if [ "${BRANCH}" = "snapshot" ]; then
    pkg_version="$(echo "${pkg_version}" | \
	sed "s@\([0-9]\.[0-9]\.[0-9]\)-\(.*\)@\1.999-\2@")-daily"
fi

# ----------------------------------
# --> P A C K A G E  U P D A T E <--
# ----------------------------------

# 6. Update the GBP config file
sed -i -e "s,^\(debian-branch\)=.*,\1=${BRANCH}/debian/${DIST}," \
       -e "s,^\(debian-tag\)=.*\(/\%.*\),\1=${BRANCH}/debian/${DIST}\2," \
       -e "s,^\(upstream-.*\)=.*,\1=${branch},"  debian/gbp.conf

# 7. Update and commit
echo "=> Update and commit the changelog"
if [ "${BRANCH}" = "snapshot" ]; then
    dist="${DIST}-daily"
    msg="daily"

    # Dirty hack, but it's the fastest, easiest way to solve
    #   E: spl-linux changes: bad-distribution-in-changes-file sid-daily
    # Don't know why I don't get that for '{wheezy,jessie}-daily as well,
    # but we do this for all of them, just to make sure.
    CHANGES_DIR="/usr/share/lintian/vendors/debian/main/data/changes-file"
    mkdir -p "${CHANGES_DIR}"
    if [ ! -f "${CHANGES_DIR}/known-dists" ]
    then
	echo "${dist}" >  "${CHANGES_DIR}/known-dists"
    else
	echo "${dist}" >> "${CHANGES_DIR}/known-dists"
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
    apt-get update > /dev/null 2>&1
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
git push --all

# Record changes
echo "=> Recording successful build (${sha})"
echo "${sha}" > "/tmp/docker_scratch/lastSuccessfulSha-${APP}-${DIST}-${BRANCH}"
