#!/bin/sh -xe

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
# If running under Jenkins, it is/should be responsible for checking out
# the code into WORKDIR. If $JENKINS_HOME is NOT set (as in not running
# under Jenkins), the code will be cloned and checked out.
#
# Copyright 2016 Turbo Fredriksson <turbo@bayour.com>.
# Released under GPL, version of your choosing.

echo "=> Building (${APP}/${DIST}/${BRANCH})"

# If we haven't mounted the $HOME/.ssh directory into the Docker container,
# the known_hosts don't exit. However, if we have a local copy (in the
# scratch dir), then use that.
# To avoid a 'Do you really want to connect' question, make sure that the
# hosts we're using is all in there.
if [ ! -f "${HOME}/.ssh/known_hosts" -a "/tmp/docker_scratch/known_hosts" ]
then
    # We probably don't have the .ssh directory either, so create it.
    [ -d "${HOME}/.ssh" ] || mkdir -p "${HOME}/.ssh"
    cp /tmp/docker_scratch/known_hosts "${HOME}/.ssh/known_hosts"
fi

# --------------------------------
# --> C O D E  C H E C K O U T <--
# --------------------------------

if [ -z "${JENKINS_HOME}" ]; then
    # Checking out the code.
    git clone --origin pkg-${APP} ${GIT_APP_REPO}
    cd pkg-${APP}

    # Add remote ${APP}.
    git remote add ${APP} git@github.com:zfsonlinux/${APP}.git
    git fetch ${APP}
fi

# ----------------------------------
# --> C O D E  D I S C O V E R Y <--
# ----------------------------------

# NOTE: Jenkins checkes out a commitId, even if a branch is specified!!
#       Also, it don't seem to be possible to use build variables in there.

# 1. Checkout the correct branch.
if ! git show pkg-${APP}/${BRANCH}/debian/${DIST} > /dev/null 2>&1; then
    # Branch don't exist - use the 'jessie' branch, because that's currently the latest.
    # If the system is very different from this, the build will probably fail, but it's
    # a start.
    git checkout -b ${BRANCH}/debian/${DIST} pkg-${APP}/${BRANCH}/debian/jessie
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
if [ "${FORCE}" = "false" -a \
     -f "/tmp/docker_scratch/lastSuccessfulSha-${APP}-${DIST}-${BRANCH}" ]
then
    file="/tmp/docker_scratch/lastSuccessfulSha-${APP}-${DIST}-${BRANCH}"
    old="$(cat "${file}")"
    if [ "${sha}" = "${old}" ]; then
        echo "=> No point in building - same as previous version."
        exit 0
    fi
fi

# 4. Get the latest upstream tag.
#    If there's no changes, exit successfully here.
#    However, if we're called with FORCE set, then ignore this and continue anyway.
git merge -Xtheirs --no-edit ${branch} 2>&1 | \
    grep -q "^Already up-to-date.$" && \
    no_change=1
if [ "${FORCE}" = "false" -a "${no_change}" = "1" -a "${DIST}" != "sid" ]
then
    echo "=> No point in building - same as previous version."
    exit 0
fi

# 5. Calculate the next version.
#    Some ugly magic here.
nr="$(head -n1 debian/changelog | sed -e "s@.*(\(.*\)).*@\1@" \
    -e "s@^\(.*\)-\([0-9]\+\)-\(.*\)\$@\2@" -e "s@^\(.*\)-\([0-9]\+\)\$@\2@")"
pkg_version="$(git describe ${branch} | sed "s@^${APP}-@@")"
if [ "${BRANCH}" = "snapshot" ]; then
    pkg_version="$(echo "${pkg_version}" | \
	sed "s@\([0-9]\.[0-9]\.[0-9]\)-\(.*\)@\1.999-\2@")-${DIST}-daily"
else
    pkg_version="${pkg_version}-$(expr ${nr} + 1)-${DIST}"
fi

# ----------------------------------
# --> P A C K A G E  U P D A T E <--
# ----------------------------------

# 6. Setup debian directory.
echo "=> Start with a clean debian/controls file"
debian/rules override_dh_prep-base-deb-files

# 7. Update the GBP config file
sed -i -e "s,^\(debian-branch\)=.*,\1=${BRANCH}/debian/${DIST}," \
       -e "s,^\(debian-tag\)=.*\(/\%.*\),\1=${BRANCH}/debian/${DIST}\2," \
       -e "s,^\(upstream-.*\)=.*,\1=${branch},"  debian/gbp.conf

# 8. Update and commit
echo "=> Update and commit the changelog"
if [ "${BRANCH}" = "snapshot" ]; then
    dist="${DIST}-daily"
    msg="daily"

    # Dirty hack, but it's the fastest, easiest way to solve
    #   E: spl-linux changes: bad-distribution-in-changes-file sid-daily
    # Don't know why I don't get that for '{wheezy,jessie}-daily as well,
    # but we do this for all of them, just to make sure.
    CHANGES_DIR="/usr/share/lintian/vendors/debian/main/data/changes-file"
    sudo mkdir -p "${CHANGES_DIR}"
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

changed="$(git status | grep -E 'modified:|deleted:|new file:' | wc -l)"
if [ "${changed}" -gt 0 ]; then
    # Only change the changelog if we have to!
    debchange --distribution "${dist}" --newversion "${pkg_version}" \
	      --force-bad-version --force-distribution \
	      --maintmaint "New $msg release - ${sha}."
fi


# -----------------------------------
# --> S T A R T  T H E  B U I L D <--
# -----------------------------------

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

[ "${FORCE}" = "true" ] && retag="--git-retag"
${gbp} --git-ignore-branch --git-keyid="${GPKGKEYID}" --git-tag \
       --git-ignore-new --git-builder="debuild -i -I -k${GPGKEYID}" \
       ${retag}


# ------------------------
# --> F I N I S H  U P <--
# ------------------------

# Upload packages
echo "=> Upload packages"
changelog="/home/jenkins/build/${APP}-linux_$(head -n1 debian/changelog | \
    sed "s@.*(\(.*\)).*@\1@")_$(dpkg-architecture -qDEB_BUILD_ARCH).changes"
[ -z "${NOUPLOAD}" ] && dupload "${changelog}"

# Copy artifacts so they can be archived in Jenkins.
mkdir -p artifacts
cat "${changelog}" | \
while read line; do
    # Read up to the first '^Checksums-*' line.
    if echo "${line}" | grep -q "^Checksums-"; then
        files="$(while read line; do
	    # Keep reading up to next '^Checksums-*' line.
	    echo "${line}" | grep -Eq "^Checksums-" && \
	    break || \
	    echo "${line}" | sed 's@.* @../@'
	done)"

	IFS="
"
	cp $(echo "${files}") "${changelog}" artifacts/
	break
    fi
done

# TODO: Let Jenkins deal with this?
#if [ -z "${JENKINS_HOME}" ]; then
    if [ "${changed}" ]; then
	# Setup user for commits.
	git config --global user.name "${GITNAME}"
	git config --global user.email "${GITEMAIL}"

	git add META debian/changelog debian/gbp.conf
	git commit -m "New daily release - $(date -R)/${sha}."
    fi

    # Push our changes to GitHub
    #git push --all
#fi

# Record changes
echo "=> Recording successful build (${sha})"
echo "${sha}" > "/tmp/docker_scratch/lastSuccessfulSha-${APP}-${DIST}-${BRANCH}"
