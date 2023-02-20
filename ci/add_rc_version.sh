#!/bin/bash

# Check if the current branch name matches the pattern VERSION-X.Y.Z
branch_name=$(git rev-parse --abbrev-ref HEAD)
if [[ ! $branch_name =~ ^VERSION-[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Branch name does not match the pattern VERSION-X.Y.Z"
  exit 1
fi

# Get the latest tag that matches the pattern X.Y.Z-rcN
last_tag=$(git describe --abbrev=0 --tags --match "[0-9]*.[0-9]*.[0-9]*-rc[0-9]*" 2>/dev/null)

# Get the current version number and release candidate number
if [[ -n $last_tag ]]; then
  version=$(echo $last_tag | sed 's/-rc[0-9]*$//')
  rc_num=$(echo $last_tag | grep -oP '(?<=-rc)[0-9]*')
  rc_num=$((rc_num + 1))
else
  # Set the initial version number based on the current branch name
  version=$(echo $branch_name | sed 's/^VERSION-//;s/\//./g')
  rc_num=1
fi

# Create the new tag
new_tag="${version}-rc${rc_num}"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_tag/" .mvn/maven.config

git tag $new_tag