#!/bin/sh

# Paths to the repo and incoming directory. This should be the only manual
# change needed.
S3_REPO_DIR="/home/ftp/zol/debian"
INCOMING_DIR="/usr/src/incoming.jenkins"

# Delete old files in the repo.
#DELETE="--delete-removed --delete-after"

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

# Start a GNUPG Agent and prime the passphrase so that signing of the
# packages etc work without intervention.
echo "=> Start and prime gnupg"
if ! gpg-connect-agent /bye 2> /dev/null; then
	eval $(gpg-agent --daemon --allow-preset-passphrase \
		--write-env-file "${HOME}/.gpg-agent.info")
fi
echo "${GPGPASS}" | /usr/lib/gnupg2/gpg-preset-passphrase  -v -c ${GPGCACHEID}

# Go to the S3 repository 'checkout' and use reprepro to add the changes
# to the repo.
cd "${S3_REPO_DIR}"
find "${INCOMING_DIR}" -type f -name "*.changes" 2> /dev/null | sort | \
while read changes; do
	# Get the distribution from the changes file.
	dist="$(grep "^Distribution:" "$changes" | sed 's@.*: @@')"

echo	reprepro include "${dist}" "${changes}"
done

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

# Syncronize the repository
#s3cmd sync $DELETE --acl-public ./ s3://archive.zfsonlinux.org/debian/

# Kill the GPG Agent
echo "${GPG_AGENT_INFO}" | sed "s,.*:\(.*\):.*,\1," | \
    xargs --no-run-if-empty kill
