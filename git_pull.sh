#!/bin/sh -e

if git status | egrep -q 'modified:|new file:|deleted:'; then
	echo "=> git stash save"
	git stash save "git pulling"
	STASH_SAVED=yes
fi

echo "=> git fetch"
git fetch --recurse-submodules

if [ -f ".gitmodules" ]; then
	echo "=> git submodule update"
	git submodule update --recursive
fi

echo "=> git slog origin/master..HEAD"
git log --pretty=oneline --abbrev-commit origin/master..HEAD

echo "=> git rebase origin/master"
git rebase origin/master

if [ -n "${STASH_SAVED}" ]; then
	echo "=> git stash pop"
	git stash pop
fi

echo "=> git slog origin/master..HEAD"
git log --pretty=oneline --abbrev-commit origin/master..HEAD

echo "=> git stash list"
git stash list
