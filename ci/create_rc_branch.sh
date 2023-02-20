#!/bin/bash

# Check if the current branch name matches the pattern master
branch_name=$(git rev-parse --abbrev-ref HEAD)
if [[ ! $branch_name =~ ^master$ ]]; then
  echo "Error: You should create a RC branch from the master branch."
  exit 1
fi

# get the latest tag
git fetch --tags
tag=$(git tag --sort=-v:refname | grep -E '^[0-9]*+\.[0-9]*+\.[0-9]*+-SNAPSHOT$' | head -n1)

# get the major, minor, and patch numbers
if [[ $tag =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-SNAPSHOT ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
else
    echo "Error: tag ($tag) is not in the correct format" >&2
    exit 1
fi

# End of getting values, going to RC branch.
branch="VERSION-${major}.${minor}.${patch}"
new_tag="${major}.${minor}.${patch}-rc0"

# create RC branch
git checkout -b "$branch"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_tag/" .mvn/maven.config
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_tag"

# push the new tag and branch to remote
git push --set-upstream origin "$branch"

# back to master branch to continue the job.
git checkout master
patch=$((patch + 1))
new_tag="${major}.${minor}.${patch}"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_tag/" .mvn/maven.config

# Do the commit in master branch
git config --global user.email "glaucio.porcidesczekailo@atos.net"
git config --global user.name "Glaucio Czekailo"
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
git tag "$new_tag"
git push origin master