#!/bin/bash

# Description:
### This script can run only on master and it will continue on the release branch if the previous tag contains -RCN-SNAPSHOT in the name
### This is common code for Release RC and for the HF RC


# Check if the current branch name matches the pattern master
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ ! $BRANCH =~ ^master$ ]]; then
  echo "Error: This script can be called only from the master."
  exit 1
fi

# Get the branch name where the new RC will be built
# Check if the second argument exists
if [ -z "$1" ]; then
    echo "Error: Branch name argument is missing"
	exit 1
else
	branch_name="$1"
fi

# Get the release type of this new branch
# Check if the second argument exists
if [ -z "$2" ]; then
    release_type="rc"
else
	release_type="$2"
	if [[ "$release_type" != "final" ]]; then
		echo "Error: Release type argument can be empty or 'final'"
		exit 1
	fi
fi

#switch to the release branch and continue
git fetch
git checkout $branch_name

# Check if the previous tag follows the format X.Y.Z(-HFN)-RCN-SNAPSHOT
# get the latest tag
git fetch --tags
#tag=$(git describe --tags --abbrev=0) # fails on Github
tag=$(git tag --merged $branch_name --sort=-v:refname | head -n1)

isHF=false
# get the major, minor, patch, RC and HF on else branch 
if [[ $tag =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)-SNAPSHOT ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
	rc=${BASH_REMATCH[4]}
elif [[ $tag =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)-SNAPSHOT ]]; then
	major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
	hf=${BASH_REMATCH[4]}
	rc=${BASH_REMATCH[5]}
	isHF=true;
else
    echo "Error: tag ($tag) is not in the correct format" >&2
    exit 1
fi

# Setup RC tag for this build
new_rc_version="${major}.${minor}.${patch}"
if [ "$isHF" = false ]; then
	if [[ "$release_type" == "final" ]] then
		new_rc_qualifier=""
	else
		new_rc_qualifier="-RC$rc"
	fi
else
	if [[ "$release_type" == "final" ]] then
		new_rc_qualifier="-HF$hf"
	else
		new_rc_qualifier="-HF$hf-RC$rc"
	fi
fi

# Setup RC tag name for future development builds on this release branch
future_rc_version="${major}.${minor}.${patch}"
if [[ "$release_type" == "final" ]] then
	rc="1"
else
	((rc++))
fi	

if [ "$isHF" = false ]; then
	if [[ "$release_type" == "final" ]] then
		future_rc_qualifier="-HF1-RC$rc-SNAPSHOT"
	else 
		future_rc_qualifier="-RC$rc-SNAPSHOT"
	fi	
else
	if [[ "$release_type" == "final" ]] then
		((hf++))
	fi
	future_rc_qualifier="-HF$hf-RC$rc-SNAPSHOT"
fi
echo "1. will work on branch $branch_name"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_rc_version/" .mvn/maven.config
sed -i "s/-Dchangelist=.*/-Dchangelist=$new_rc_qualifier/" .mvn/maven.config
echo "2. will update .mvn/maven.config on branch to $new_rc_version and $new_rc_qualifier"

git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_rc_version$new_rc_qualifier" "$branch_name"
echo "3. will commit the .mvn/maven.config changes and  create a tag $new_rc_version$new_rc_qualifier to branch: $branch_name"

# Build goes here
#
#
echo "4. Build goes here"

if [[ "$release_type" == "final" ]] then
	echo "4.1 This a final release build, the result should go on some SERVER here" 
fi

# Update the Maven version in the maven.config file for future RC builds
sed -i "s/-Drevision=.*/-Drevision=$future_rc_version/" .mvn/maven.config
sed -i "s/-Dchangelist=.*/-Dchangelist=$future_rc_qualifier/" .mvn/maven.config
echo "5. will update .mvn/maven.config on branch $branch_name to $future_rc_version and $future_rc_qualifier"

git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$future_rc_version$future_rc_qualifier" "$branch_name"
echo "6. will commit the .mvn/maven.config changes and  create a tag $future_rc_version$future_rc_qualifier" 

git push --tags #not recommended
git push
echo "7. will push the new maven version and tags to $branch_name"