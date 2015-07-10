#!/bin/sh

find -name .gitignore | xargs --no-run-if-empty rm
git clean --force -d
git reset --hard
