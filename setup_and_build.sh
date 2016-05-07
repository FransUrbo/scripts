#!/bin/sh

set -x
set -e

# Path to the actual build script. This should be the only manual change
# needed.
BUILD_SCRIPT="${HOME}/bin/build_zol.sh"

# ========================================================================
# This is the primary build script (of two) intended to build ZFS On Linux
# Debian GNU/Linux packages.
#
# It will start a GNUPG Agent, prime the passphrase and then start a
# Docker container and in that run the second, actual, build script.
#
# It is intended (built for) to run from a Jenkins multi-configuration
# project. To avoid hard coded values in the scripts, it require some
# environment variables injected into the build process:
#   * As build parameters:
#     These will be passed on to the build script, and can there for be
#     seen in a 'ps' output!
#     APP		What repository to build (spl, zfs)
#     DIST		What distribution to build for (wheezy, jessie, sid)
#     BRANCH		What base branch to build (master, snapshot)
#   * From the 'Environment Injector' plugin:
#     + As a 'normal' environment variable
#       These will be passed on to the build script, and can there for be
#       seen in a 'ps' output!
#       GITNAME		Full name to use for commits
#       GITEMAIL	Email address to use for commits
#       GPGKEYID	GPG Key ID
#     + As a password environment variable (will be masked).
#       These will NOT be passed on to the build script.
#       GPGCACHEID	GPG Key ID. See gpg-preset-passphrase(1)
#       GPGPASS		GPG Passphrase
# If not running from Jenkins, set this in the environment normaly.
#
# The 'WORKSPACE' variable is set by Jenkins for every job and is the path
# to the base build directory (where the GIT project is checked out and
# build), but if it's not set, it will be set in the script to something
# resonable.
#
# Copyright 2016 Turbo Fredriksson <turbo@bayour.com>.
# Released under GPL, version of your choosing.
# ========================================================================

if echo "${*}" | grep -qi "help"; then
    echo "Usage: $(basename ${0}) <app> <dist> <branch>"
    exit 1
elif [ -n "${1}" -a -n "${2}" -a -n "${3}" ]; then
    APP="${1}" ; DIST="${2}" ; BRANCH="${3}"
fi

if [ -z "${APP}" -o -z "${DIST}" -o -z "${BRANCH}" -o -z "${GITNAME}" \
	-o -z "${GITEMAIL}" -o -z "${GPGCACHEID}" -o -z "${GPGPASS}" \
	-o -z "${GPGKEYID}" ]
then
    echo -n "ERROR: One (or more) of APP, DIST, BRANCH, GITNAME, GITEMAIL, "
    echo -n "GPGCACHEID, GPGPASS and/or GPGKEYID environment variable is "
    echo "missing!"
    echo "Usage: $(basename "${0}") <app> <dist> <branch>"
    exit 1
fi

# This can be randomized if it's not supplied. This so that we
# can run this from the shell if we want to.
[ -z "${WORKSPACE}" ] && WORKSPACE="/tmp/docker_build-${APP}_$$"

echo "=> Setting up a Docker build (${APP}/${DIST}/${BRANCH})"

if [ -n "${TERM}" ]; then
    # Should be interactive...
# When we want to run interactivly, remove this comment and change
# the docker script at the bottom to 'bash'.    
#    IT="-it"
    mkdir -p "${WORKSPACE}"
fi

# Start a GNUPG Agent and prime the passphrase so that signing of the
# packages etc work without intervention.
echo "=> Start and prime gnupg"
eval $(gpg-agent --daemon --allow-preset-passphrase \
		 --write-env-file "${WORKSPACE}/.gpg-agent.info")
echo "${GPGPASS}" | /usr/lib/gnupg2/gpg-preset-passphrase -v -c ${GPGCACHEID}

# Copy built script.
echo "=> Copying build script"
cp "${BUILD_SCRIPT}" ${WORKSPACE}

# Start a docker container.
# Inside there is where the actual build takes place, using the
# 'build_zol.zh' script.
echo "=> Starting docker image debian:${DIST}-devel"
docker -H tcp://127.0.0.1:2375 run \
       -v ${HOME}/.ssh:/root/.ssh \
       -v ${HOME}/.gnupg:/root/.gnupg \
       -v $(dirname ${SSH_AUTH_SOCK}):$(dirname ${SSH_AUTH_SOCK}) \
       -v $(dirname ${GPG_AGENT_INFO}):$(dirname ${GPG_AGENT_INFO}) \
       -v ${WORKSPACE}:${WORKSPACE} -w ${WORKSPACE} \
       -e APP="${APP}" -e DIST="${DIST}" -e BRANCH="${BRANCH}" \
       -e LOGNAME="${LOGNAME}" -e SSH_AUTH_SOCK="${SSH_AUTH_SOCK}" \
       -e GPG_AGENT_INFO="${GPG_AGENT_INFO}" -e WORKSPACE="${WORKSPACE}" \
       -e GITNAME="${GITNAME}" -e GITEMAIL="${GITEMAIL}" \
       -e GPGKEYID="${GPGKEYID}" --rm ${IT} debian:${DIST}-devel \
       ./build_zol.sh ${APP} ${DIST} ${BRANCH}

# Kill the GPG Agent
echo "${GPG_AGENT_INFO}" | sed "s,.*:\(.*\):.*,\1," | \
    xargs --no-run-if-empty kill
