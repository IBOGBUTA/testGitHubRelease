#!/bin/bash

# Description:
### This script can run only on master branch

RUN_PATH=$(dirname "${BASH_SOURCE[0]}")

source $RUN_PATH/common_release_functions.sh || { LOG -e "Cannot reach external resource $RUN_PATH/common_release_functions.sh. Will exit."; exit 1; }
TAG_FORMAT_ON_MASTER="^[0-9]*+\.[0-9]*+\.[0-9]*+-SNAPSHOT$"
TAG_PATTERN_ON_MASTER="([0-9]+)\.([0-9]+)\.([0-9]+)-SNAPSHOT"
TAG_FORMAT_SNAPSHOT_RC="^[0-9]*+\.[0-9]*+\.[0-9]*+-((HF[0-9]+-RC[0-9]+)|(RC[0-9]+))-SNAPSHOT$"
TAG_PATTERN_SNAPSHOT_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)-SNAPSHOT$"

## readyForNewReleaseBranch()
## This function will check all existing branches that match the format VERSION-* if the last commit
## matches the format corresponding to release development phase X.Y.Z-RCN-SNAPSHOT.
## returns:
##			0 - if all tags match the format X.Y.Z-HFN-RCN-SNAPSHOT
##			1 - if any matches the format X.Y.Z-RCN-SNAPSHOT - this indicates the fact that this version wasn't released yet
function readyForNewReleaseBranch() {
    git checkout master >/dev/null 2>&1
    git ls-remote --heads origin | awk -F "/" '/VERSION-*/ {print $NF}' | {
    safeToBranchOff=0
    while read available_branch; do 
        git checkout $available_branch >/dev/null 2>&1
        latest_snapshot_tag=$(git for-each-ref --sort=-creatordate --format '%(refname:short)' refs/tags --merged $available_branch | grep -E $TAG_FORMAT_SNAPSHOT_RC | head -1)        
        if [[ $latest_snapshot_tag =~ $TAG_PATTERN_SNAPSHOT_RELEASE ]]; then
            LOG -e "Branch $available_branch is stil in development. Latest SNAPSHOT tag on $available_branch is $latest_snapshot_tag"
            safeToBranchOff=1
        fi
    done
    exit $safeToBranchOff
    }
    RC=$?
    git checkout master >/dev/null 2>&1
    return $RC
}

# This script can run only on master branch
runningOnMaster && { LOG "$0 called from master. Script can continue."; } || { LOG -e "You should create a RC branch from the master branch."; exit 1; }

# Get the release type of this new branch
# Check if the first argument exists
if [ -z "$1" ]; then
    LOG -e "Release type argument missing. Possible values: major, minor, patch"
    exit 1
fi
release_type="$1"

if [[ "$release_type" == "major" || "$release_type" == "minor" || "$release_type" == "patch" ]]; then
    LOG "$0 called with release type: $release_type. Script can continue."
else
    LOG -e "Unknown release type: $release_type. Possible values: major, minor, patch"
    exit 1
fi

# get the latest tag
git fetch --tags >/dev/null 2>&1

# Make sure all branches are available only for HF release.
readyForNewReleaseBranch && LOG "New branch can be created. There's no open development branch or they all reached HF phase." || exit 1

tag=$(git tag --sort=-v:refname | grep -E $TAG_FORMAT_ON_MASTER | head -n1)

# get the major, minor, and patch
if [[ $tag =~ $TAG_PATTERN_ON_MASTER ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
else
    LOG -e "Latest tag on master ($tag) is not in the correct format." >&2
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

# Setup new master tag
((master_patch=patch+1))
new_master_version="${major}.${minor}.${master_patch}"
new_master_qualifier="-SNAPSHOT"

LOG "New $release_type release version branch will be named VERSION-${major}.${minor}.${patch}"
# Setup new branch name
branch="VERSION-${major}.${minor}.${patch}"

# Setup RC tag name for future development builds on this release branch
future_rc_version="${major}.${minor}.${patch}"
future_rc_qualifier="-RC1-SNAPSHOT"

# create RC branch
git checkout -b "$branch" >/dev/null 2>&1

# update Maven config on release branch
updateMavenConfig "$future_rc_version" "$future_rc_qualifier" && 
	{ LOG "Updating .mvn/maven.config on branch $branch to $future_rc_version$future_rc_qualifier"; } || 
	{ LOG -e "Failed to update Maven Config to $future_rc_version$future_rc_qualifier"; exit 1; }
git diff --exit-code --quiet .mvn/maven.config || git commit -m "[WF] Automatic update of Maven version to $future_rc_version$future_rc_qualifier" .mvn/maven.config
git tag "$future_rc_version$future_rc_qualifier" "$branch" >/dev/null 2>&1
LOG "Actions done on branch $branch: New commit for the .mvn/maven.config changes, new tag $future_rc_version$future_rc_qualifier created." 

# back to master branch to continue the job.
git checkout master >/dev/null 2>&1

# update Maven config on master
updateMavenConfig "$new_master_version" "$new_master_qualifier" && 
	{ LOG "Updating .mvn/maven.config on master to $new_master_version$new_master_qualifier"; } || 
	{ LOG -e "Failed to update Maven Config to $new_master_version$new_master_qualifier"; exit 1; }
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of Maven version to $new_master_version$new_master_qualifier" .mvn/maven.config
git tag "$new_master_version$new_master_qualifier" master
LOG "Actions done on master: New commit for the .mvn/maven.config changes, new tag $new_master_version$new_master_qualifier." 

git checkout "$branch" >/dev/null 2>&1
git push --set-upstream origin "$branch" >/dev/null 2>&1
git push --tags >/dev/null 2>&1
LOG "Changes on branch $branch saved"

git checkout master >/dev/null 2>&1
git push origin master >/dev/null 2>&1
git push --tags >/dev/null 2>&1
LOG "Changes on master saved"