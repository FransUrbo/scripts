#!/bin/sh

git commit $(git status | grep modified: | sed 's@.*:   @@')
