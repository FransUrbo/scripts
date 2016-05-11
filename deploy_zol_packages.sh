#!/bin/sh

# Paths to the repo and incoming directory. This should be the only manual
# change needed.
S3_REPO_DIR="/home/ftp/zol/debian"
INCOMING_DIR="/usr/src/incoming.jenkins"

# Delete old files in the repo.
#DELETE="--delete-removed --delete-after"

# Default reprepro options.
REPREPRO="reprepro --ignore=surprisingbinary --export=never"

# No checking for correct, missing or faulty values will be done in this
# script. This is the third part of a automated build process and is intended
# to run inside a Docker container. See comments in 'setup_and_build.sh' for
# more information.
#
# Copyright 2016 Turbo Fredriksson <turbo@bayour.com>.
# Released under GPL, version of your choosing.

# Start a GNUPG Agent and prime the passphrase so that signing of the
# packages etc work without intervention.

set -e


# -----------------------------------------
# --> S T A R T   G N U P G   A G E N T <--
# -----------------------------------------

# Start a GNUPG Agent and prime the passphrase so that signing of the
# packages etc work without intervention.
echo "=> Start and prime gnupg"
if ! gpg-connect-agent /bye 2> /dev/null; then
	eval $(gpg-agent --daemon --allow-preset-passphrase \
		--write-env-file "${HOME}/.gpg-agent.info")
fi
echo "${GPGPASS}" | /usr/lib/gnupg2/gpg-preset-passphrase  -v -c ${GPGCACHEID}

cd "${S3_REPO_DIR}"


# -------------------------
# --> S Y N C   R E P O <--
# -------------------------

# Syncronize the repository
s3cmd sync --skip-existing $DELETE s3://archive.zfsonlinux.org/debian/ ./


# -----------------------------
# --> U P D A T E   R E P O <--
# -----------------------------

# Update dists links.
echo "=> Update dists links"
reprepro --delete createsymlinks

# Use reprepro to add the changes to the repo.
find "${INCOMING_DIR}" -type f -name "*.changes" 2> /dev/null | sort | \
while read changes; do
    done="$(echo "${changes}" | sed 's@\.changes@\.done@')"
    if [ ! -f "${done}" ]; then
	# Get the distribution from the changes file.
	dist="$(grep "^Distribution:" "${changes}" | sed 's@.*: @@')"
	echo "=> include ${dist} ${changes}"

	if [ "${dist}" = "zfsonlinux" ]; then
	    # This is probably the 'zfsonlinux' meta package. Install it
	    # everywhere.
	    for dist in $(grep '^Codename:' conf/distributions | \
		egrep -v 'daily|installer' | sed 's@.*: @@')
	    do
		for subdist in "" -daily; do
		    ${REPREPRO} --ignore=wrongdistribution include \
			${dist}${subdist} "${changes}"
		    [ "$?" ] && touch "${done}"
		done
	    done
	else
	    ${REPREPRO} include "${dist}" "${changes}"
	    [ "$?" ] && touch "${done}"
	fi
    fi
done

# Exporting indices.
echo "=> Exporting indices"
reprepro export

# -----------------------
# --> F I X   R E P O <--
# -----------------------

# Cleanup/fixup the repo.
# * S3 can't handle files with a '+' in them, so replace it with a space.
find -name '*+*' | \
while read file; do
    new=`echo "$file" | sed 's@\+@ @g'`
    if [ ! -e "$new" ]; then
	echo -n "Creating '+' link for '$file': "
	pushd "$(dirname "$new")" > /dev/null 2>&1
	if file "$(basename "$file")" | grep -q ': directory'; then
	    cp -r "$(basename "$file")" "$(basename "$new")"
	else
	    ln "$(basename "$file")" "$(basename "$new")"
	fi
	popd > /dev/null 2>&1
	echo "done."
    fi
done


# -------------------------
# --> S Y N C   R E P O <--
# -------------------------

# Syncronize the repository
#s3cmd sync $DELETE --acl-public ./ s3://archive.zfsonlinux.org/debian/

# Kill the GPG Agent
echo "${GPG_AGENT_INFO}" | sed "s,.*:\(.*\):.*,\1," | \
    xargs --no-run-if-empty kill
