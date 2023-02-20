#!/bin/bash

# Check if the current branch name matches the pattern main
branch_name=$(git rev-parse --abbrev-ref HEAD)
if [[ ! $branch_name =~ ^main$ ]]; then
  echo "Error: You should create a RC branch from the main branch."
  exit 1
fi

# get the latest tag
git fetch
tag=$(git describe --abbrev=0 --tags --match "[0-9]*.[0-9]*.[0-9]*-SNAPSHOT" 2>/dev/null)

# get the major, minor, and patch numbers
if [[ $tag =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-SNAPSHOT ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
else
    echo "Error: tag ($tag) is not in the correct format" >&2
    exit 1
fi

# increment the patch number and update maven.config with new version
patch=$((patch + 1))
new_tag="${major}.${minor}.${patch}-SNAPSHOT"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_tag/" .mvn/maven.config

# Do the commit in main branch
git config --global user.email "glaucio.porcidesczekailo@atos.net"
git config --global user.name "Glaucio Czekailo"
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_tag"
git push origin main

# End of handling main branch, going to RC branch.
branch="VERSION-${major}.${minor}.${patch}"
new_tag="${major}.${minor}.${patch}-rc0"

# create the new branch
git checkout -b "$branch"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_tag/" .mvn/maven.config
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_tag"

# push the new tag and branch to remote
git push --set-upstream origin "$branch"
git push origin "$new_tag"