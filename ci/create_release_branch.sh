#!/bin/bash

# Description:
### This script can run only on master branch

# Git setup
#git config --global user.email "bogdan.buta@atos.net"
#git config --global user.name "Bogdan Buta"

# Check if the current branch name matches the pattern master
branch_name=$(git rev-parse --abbrev-ref HEAD)
if [[ ! $branch_name =~ ^master$ ]]; then
  echo "Error: You should create a RC branch from the master branch."
  exit 1
fi

# Get the release type of this new branch
# Check if the first argument exists
if [ -z "$1" ]; then
    echo "Error: Release type argument missing. Possible values: major, minor, patch"
    exit 1
fi
release_type="$1"

if [[ "$release_type" == "major" || "$release_type" == "minor" || "$release_type" == "patch" ]]; then
    echo "A new branch for a $release_type release will be created."
else
    echo "Error: Incorrect release type. Possible values: major, minor, patch"
    exit 1
fi

# get the latest tag
git fetch --tags
tag=$(git tag --merged master --sort=-v:refname | grep -E '^[0-9]*+\.[0-9]*+\.[0-9]*+-SNAPSHOT$' | head -n1)

# get the major, minor, and patch
if [[ $tag =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-SNAPSHOT ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
else
    echo "Error: tag ($tag) is not in the correct format" >&2
    exit 1
fi

if [[ "$release_type" == "major" ]]; then
	((major++))
	minor=0
	patch=0
elif [[ "$release_type" == "minor" ]]; then
	((minor++))
	patch=0	
else 
	#patch release, will use the tag on the the master
	#nothing to do here for now	
	echo "New patch, will user version on master branch"
fi

echo "New $release_type release version base will be ${major}.${minor}.${patch}"

# Setup new branch name
branch="VERSION-${major}.${minor}.${patch}"

# Setup new RC tag name for initial build
new_rc_version="${major}.${minor}.${patch}"
new_rc_qualifier="-RC1"

# Setup RC tag name for future development builds on this release branch
future_rc_version="${major}.${minor}.${patch}"
future_rc_qualifier="-RC2-SNAPSHOT"

# Setup new master tag
((master_patch=patch+1))
new_master_version="${major}.${minor}.${master_patch}"
new_master_qualifier="-SNAPSHOT"

# create RC branch
git checkout -b "$branch"
echo "1. will checkout branch $branch"


# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_rc_version/" .mvn/maven.config
sed -i "s/-Dchangelist=.*/-Dchangelist=$new_rc_qualifier/" .mvn/maven.config
echo "2. will update .mvn/maven.config on branch to $new_rc_version and $new_rc_qualifier"


#drop the snapshot for now
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_rc_version$new_rc_qualifier" "$branch"
echo "3. will commit the .mvn/maven.config changes and  create a tag $new_rc_version$new_rc_qualifier"  


# Build goes here
#
#
echo "4. Build goes here"

# Update the Maven version in the maven.config file for future RC builds
sed -i "s/-Drevision=.*/-Drevision=$future_rc_version/" .mvn/maven.config
sed -i "s/-Dchangelist=.*/-Dchangelist=$future_rc_qualifier/" .mvn/maven.config
echo "5. will update .mvn/maven.config on branch to $future_rc_version and $future_rc_qualifier"

git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$future_rc_version$future_rc_qualifier" "$branch"
echo "6. will commit the .mvn/maven.config changes and  create a tag $future_rc_version$future_rc_qualifier" 

# push the new tags and branch to remote
git push --set-upstream origin "$branch"
git push --tags #not recommended
echo "7. will push the branch $branch"

# back to master branch to continue the job.
git checkout master
echo "8. will move to master"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_master_version/" .mvn/maven.config
sed -i "s/-Dchangelist=.*/-Dchangelist=$new_master_qualifier/" .mvn/maven.config
echo "9. will update .mvn/maven.config on master to $new_master_version and $new_master_qualifier"

# Do the commit in master branch
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_master_version$new_master_qualifier" master
echo "10. will commit the .mvn/maven.config changes and  create a tag $new_master_version$new_master_qualifier" 

#git push origin master
git push --tags #not recommended
git push
echo "11. will push changes to master"

