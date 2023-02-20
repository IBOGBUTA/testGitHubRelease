#!/bin/bash

# Check if the current branch name matches the pattern VERSION-X.Y.Z
branch_name=$(git rev-parse --abbrev-ref HEAD)
if [[ ! $branch_name =~ ^VERSION-[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Branch name does not match the pattern VERSION-X.Y.Z"
  exit 1
fi

# Get the latest tag that matches the pattern X.Y.Z-rcN
git fetch --tags
#last_tag=$(git describe --abbrev=0 --tags --match "[0-9]*.[0-9]*.[0-9]*-rc[0-9]*")
last_tag=$(git tag --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-rc[0-9]+$' | head -n1)

# Get the current version number and release candidate number
if [[ -n $last_tag ]]; then
  version=$(echo $last_tag | sed 's/-rc[0-9]+*$//')
  rc_num=$(echo $last_tag | grep -oP '(?<=-rc)[0-9]+')
  rc_num=$((rc_num + 1))
else
  echo "Error: tag ($last_tag) is not in the correct format" >&2
  exit 1
fi

# Create the new tag
new_tag="${version}-rc${rc_num}"

# Update the Maven version in the maven.config file
sed -i "s/-Drevision=.*/-Drevision=$new_tag/" .mvn/maven.config

git config --global user.email "glaucio.porcidesczekailo@atos.net"
git config --global user.name "Glaucio Czekailo"
git diff --exit-code --quiet .mvn/maven.config || git commit -m "Update Maven version" .mvn/maven.config
git tag $new_tag