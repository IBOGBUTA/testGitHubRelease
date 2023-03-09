#!/bin/bash

# Description:
### This script can run only on master branch

RUN_PATH=$(dirname "${BASH_SOURCE[0]}")

source $RUN_PATH/common_release_functions.sh || { echo "Error: Cannot reach external resource $RUN_PATH/common_release_functions.sh. Will exit."; exit 1; }
TAG_FORMAT_ON_MASTER="^[0-9]*+\.[0-9]*+\.[0-9]*+-SNAPSHOT$"
TAG_PATTERN_ON_MASTER="([0-9]+)\.([0-9]+)\.([0-9]+)-SNAPSHOT"

# This script can run only on master branch
runningOnMaster && { echo "$0 called from master. Script can continue."; } || { echo "Error: You should create a RC branch from the master branch."; exit 1; }

# Get the release type of this new branch
# Check if the first argument exists
if [ -z "$1" ]; then
    echo "Error: Release type argument missing. Possible values: major, minor, patch"
    exit 1
fi
release_type="$1"

if [[ "$release_type" == "major" || "$release_type" == "minor" || "$release_type" == "patch" ]]; then
    echo "$0 called with release type: $release_type. Script can continue."
else
    echo "Error: Unknown release type: $release_type. Possible values: major, minor, patch"
    exit 1
fi

# get the latest tag
git fetch --tags >/dev/null 2>&1
tag=$(git tag --sort=-v:refname | grep -E $TAG_FORMAT_ON_MASTER | head -n1)

# get the major, minor, and patch
if [[ $tag =~ $TAG_PATTERN_ON_MASTER ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
else
    echo "Error: Latest tag on master ($tag) is not in the correct format." >&2
    exit 1
fi

if [[ "$release_type" == "major" ]]; then
	((major++))
	minor=0
	patch=0
elif [[ "$release_type" == "minor" ]]; then
	((minor++))
	patch=0
fi

echo "New $release_type release version branch will be named VERSION-${major}.${minor}.${patch}"
# Setup new branch name
branch="VERSION-${major}.${minor}.${patch}"

# Setup RC tag name for future development builds on this release branch
future_rc_version="${major}.${minor}.${patch}"
future_rc_qualifier="-RC1-SNAPSHOT"

# Setup new master tag
((master_patch=patch+1))
new_master_version="${major}.${minor}.${master_patch}"
new_master_qualifier="-SNAPSHOT"

# create RC branch
git checkout -b "$branch" >/dev/null 2>&1

# update Maven config on release branch
updateMavenConfig "$future_rc_version" "$future_rc_qualifier" && 
	{ echo "Updating .mvn/maven.config on branch $branch to $future_rc_version$future_rc_qualifier"; } || 
	{ echo "Error: Failed to update Maven Config to $future_rc_version$future_rc_qualifier"; exit 1; }
git diff --exit-code --quiet .mvn/maven.config || git commit -m "[WF] Automatic update of Maven version to $future_rc_version$future_rc_qualifier" .mvn/maven.config
git tag "$future_rc_version$future_rc_qualifier" "$branch" >/dev/null 2>&1
echo "Actions done on branch $branch: New commit for the .mvn/maven.config changes, new tag $future_rc_version$future_rc_qualifier created." 

# back to master branch to continue the job.
git checkout master >/dev/null 2>&1

# update Maven config on master
updateMavenConfig "$new_master_version" "$new_master_qualifier" && 
	{ echo "Updating .mvn/maven.config on master to $new_master_version$new_master_qualifier"; } || 
	{ echo "Error: Failed to update Maven Config to $new_master_version$new_master_qualifier"; exit 1; }
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_master_version$new_master_qualifier" master
echo "Actions done on master: New commit for the .mvn/maven.config changes, new tag $new_master_version$new_master_qualifier." 

git checkout "$branch" >/dev/null 2>&1
git push --set-upstream origin "$branch" >/dev/null 2>&1
git push --tags >/dev/null 2>&1
echo "Changes on branch $branch saved"

git checkout master >/dev/null 2>&1
git push origin master >/dev/null 2>&1
git push --tags >/dev/null 2>&1
echo "Changes on master saved"