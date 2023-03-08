#!/bin/bash

#START - common functions
function updateMavenConfig() {
	if [ $# -ne 2 ]; then
		echo "Error: updateMavenConfig() - Invalid number of parameters provided. Expected 2, received $#."
		return 1
	fi
	version=$1
	qualifier=$2	
	sed -i "s/-Drevision=.*/-Drevision=$version/" .mvn/maven.config
	sed -i "s/-Dchangelist=.*/-Dchangelist=$qualifier/" .mvn/maven.config
}

#END - common functions


# Description:
### This script can run only on master and it will continue on the release branch if the previous tag contains -RCN-SNAPSHOT in the name
### This is common code for Release RC and for the HF RC

function getNextVersion() {
	# Check if the current branch name matches the pattern master
	BRANCH=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $BRANCH =~ ^master$ ]]; then
	  echo "Error: preBuildPreparation() can be called only from the master."
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
	
	# Get the release type of this new candidate
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
	git fetch >/dev/null 2>&1
	git checkout $branch_name >/dev/null 2>&1
	
	# Check if the previous tag follows the format X.Y.Z(-HFN)-RCN-SNAPSHOT
	# get the latest tag
	git fetch --tags >/dev/null 2>&1
	tag=$(git describe --tags --abbrev=0) # fails on Github
	#tag=$(git tag --merged $branch_name --sort=-v:refname | head -n1)
	
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
	
	# Setup RC tag for the upcoming build
	new_rc_version="${major}.${minor}.${patch}"
	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier=""
		else
			new_rc_qualifier="-RC$rc"
		fi
	else
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier="-HF$hf"
		else
			new_rc_qualifier="-HF$hf-RC$rc"
		fi
	fi
	
	echo "$new_rc_version$new_rc_qualifier"
	return 0	
}

function preBuildPreparation() {
	# Check if the current branch name matches the pattern master
	BRANCH=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $BRANCH =~ ^master$ ]]; then
	  echo "Error: preBuildPreparation() can be called only from the master."
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
	
	# Get the release type of this new candidate
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
	tag=$(git describe --tags --abbrev=0) # fails on Github
	#tag=$(git tag --merged $branch_name --sort=-v:refname | head -n1)

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
	
	# Setup RC tag for the upcoming build
	new_rc_version="${major}.${minor}.${patch}"
	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier=""
		else
			new_rc_qualifier="-RC$rc"
		fi
	else
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier="-HF$hf"
		else
			new_rc_qualifier="-HF$hf-RC$rc"
		fi
	fi

	echo "1. will work on branch $branch_name"

	# Update the Maven version in the maven.config file
	updateMavenConfig "$new_rc_version" "$new_rc_qualifier"	
	echo "2. will update .mvn/maven.config on branch to $new_rc_version and $new_rc_qualifier"

	git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
	git tag "$new_rc_version$new_rc_qualifier" "$branch_name"
	echo "3. will commit the .mvn/maven.config changes and  create a tag $new_rc_version$new_rc_qualifier to branch: $branch_name"
	
	echo "5. build can start now"
	git push --tags 
	git push
}

function buildPreparation() {
	# Check if the current branch name matches the pattern master
	BRANCH=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $BRANCH =~ ^master$ ]]; then
	  echo "Error: postBuildActions() can be called only from the master."
	  exit 1
	fi
	
	# Get the version of the new build
	# Check if the argument exists
	if [ -z "$1" ]; then
    	echo "Error: Version argument is missing"
		exit 1
	else
    	version="$1"
	fi
	
	# Get the release type of this new candidate
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
	
	isHF=false
	# get the major, minor, patch, RC and HF on branch 
	if [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)$ ]]; then
		echo "Request is to build new release candidate with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		rc=${BASH_REMATCH[4]}
	elif [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)$ ]]; then
		echo "Request is to build new HF release candidate with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}
		rc=${BASH_REMATCH[5]}
		isHF=true;
	elif [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)$ && "$release_type" == "final" ]]; then
		echo "Request is to build final release with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
	elif [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)$ && "$release_type" == "final" ]]; then
		echo "Request is to build final HF release with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}		
		isHF=true;
	else
		echo "Error: Version ($version) is not in the correct format" >&2
		exit 1
	fi
	
	branch_name="VERSION-${major}.${minor}.${patch}"	
    git ls-remote --exit-code --heads origin $branch_name >/dev/null 2>&1
    EXIT_CODE=$?
    if [[ $EXIT_CODE != '0' ]]; then
		echo "Error: Git branch '$branch_name' does not exist in the remote repository"
		exit 1
	fi
	
	git fetch
	git checkout $branch_name
	git fetch --tags
	
	# Setup RC tag for the build that just finished
	new_rc_version="${major}.${minor}.${patch}"
	echo "Prepare qualifier"
	if [ "$isHF" == "false" ]; then
		echo "We have a new release"
		if [[ "$release_type" == "final" ]]; then
			echo "it is a final release"
			new_rc_qualifier=""
		else
			echo "it is a new release candidate"
			new_rc_qualifier="-RC$rc"
		fi
	else
		echo "We have a new hotfix"
		if [[ "$release_type" == "final" ]]; then
			echo "it is a final HF"
			new_rc_qualifier="-HF$hf"
		else
			echo "it is a new hotfix release candidate"
			new_rc_qualifier="-HF$hf-RC$rc"
		fi
	fi
	
	# Update the Maven version in the maven.config file
	updateMavenConfig "$new_rc_version" "$new_rc_qualifier"	
	echo "2. will update .mvn/maven.config on branch to $new_rc_version and $new_rc_qualifier"
		
	# Update Helm Charts

	echo "Version files are ready. Build can continue."	
}

function postBuildActions() {
	# Check if the current branch name matches the pattern master
	BRANCH=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $BRANCH =~ ^master$ ]]; then
	  echo "Error: postBuildActions() can be called only from the master."
	  exit 1
	fi
	
	# Get the version of the new build
	# Check if the argument exists
	if [ -z "$1" ]; then
    	echo "Error: Version argument is missing"
		exit 1
	else
    	version="$1"
	fi
	
	# Get the release type of this new candidate
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
	
	isHF=false
	# get the major, minor, patch, RC and HF on branch 
	if [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)$ ]]; then
		echo "Request is to build new release candidate with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		rc=${BASH_REMATCH[4]}
	elif [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)$ ]]; then
		echo "Request is to build new HF release candidate with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}
		rc=${BASH_REMATCH[5]}
		isHF=true;
	elif [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)$ && "$release_type" == "final" ]]; then
		echo "Request is to build final release with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
	elif [[ $version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)$ && "$release_type" == "final" ]]; then
		echo "Request is to build final HF release with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}		
		isHF=true;
	else
		echo "Error: Version ($version) is not in the correct format" >&2
		exit 1
	fi
	
	branch_name="VERSION-${major}.${minor}.${patch}"	
    git ls-remote --exit-code --heads origin $branch_name >/dev/null 2>&1
    EXIT_CODE=$?
    if [[ $EXIT_CODE != '0' ]]; then
		echo "Error: Git branch '$branch_name' does not exist in the remote repository"
		exit 1
	fi
	
	git fetch
	git checkout $branch_name
	git fetch --tags
	
	# Setup RC tag for the build that just finished
	new_rc_version="${major}.${minor}.${patch}"
	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier=""
		else
			new_rc_qualifier="-RC$rc"
		fi
	else
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier="-HF$hf"
		else
			new_rc_qualifier="-HF$hf-RC$rc"
		fi
	fi
	
	# Update the Maven version in the maven.config file
	updateMavenConfig "$new_rc_version" "$new_rc_qualifier"	
	echo "2. will update .mvn/maven.config on branch to $new_rc_version and $new_rc_qualifier"
	git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
	git tag "$new_rc_version$new_rc_qualifier" "$branch_name"
	
	
	# Setup RC tag name for future development builds on this release branch
	future_rc_version="${major}.${minor}.${patch}"
	if [[ "$release_type" == "final" ]]; then
		rc="1"
	else
		((rc++))
	fi	

	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == "final" ]]; then
			future_rc_qualifier="-HF1-RC$rc-SNAPSHOT"
		else 
			future_rc_qualifier="-RC$rc-SNAPSHOT"
		fi	
	else
		if [[ "$release_type" == "final" ]]; then
			((hf++))
		fi
		future_rc_qualifier="-HF$hf-RC$rc-SNAPSHOT"
	fi	
	
	# Update the Maven version in the maven.config file for future RC builds
	updateMavenConfig "$future_rc_version" "$future_rc_qualifier"
	echo "5. will update .mvn/maven.config on branch $branch_name to $future_rc_version and $future_rc_qualifier"
	git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
	git tag "$future_rc_version$future_rc_qualifier" "$branch_name"
	echo "6. will commit the .mvn/maven.config changes and  create a tag $future_rc_version$future_rc_qualifier" 

	echo "7. will push the new maven version and tags to $branch_name in the final step"	
	git push --tags 
	git push
	
}

function revertIfBuildFails() {
	# Check if the current branch name matches the pattern master
	BRANCH=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $BRANCH =~ ^master$ ]]; then
	  echo "Error: This script can be called only from the master."
	  exit 1
	fi
	
	# Get the branch name where the revert is needed
	# Check if the first argument exists
	if [ -z "$1" ]; then
		echo "Error: Branch name argument is missing"
		exit 1
	else
		branch_name="$1"
	fi
	
	#switch to the release branch and continue
	git fetch
	git checkout $branch_name	
	git fetch --tags
	tag=$(git describe --tags --abbrev=0)
	
	#get previous tag name on the branch
	git tag -d $tag
	git push --delete origin $tag
	
	git fetch --tags
	#get previous tag name on the branch again
	tag=$(git describe --tags --abbrev=0)
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
	
	revert_version="${major}.${minor}.${patch}"
	
	if [ "$isHF" == "false" ]; then
		revert_qualifier="-RC$rc-SNAPSHOT"
	else
		revert_qualifier="-HF$hf-RC$rc-SNAPSHOT"
	fi
	
	updateMavenConfig "$revert_version" "$revert_qualifier"
	git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
	git push
	
}

#OLD CODE is still here in case we needed
function oldCode() {
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
	tag=$(git describe --tags --abbrev=0) # fails on Github
	#tag=$(git tag --merged $branch_name --sort=-v:refname | head -n1)

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
	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier=""
		else
			new_rc_qualifier="-RC$rc"
		fi
	else
		if [[ "$release_type" == "final" ]]; then
			new_rc_qualifier="-HF$hf"
		else
			new_rc_qualifier="-HF$hf-RC$rc"
		fi
	fi

	# Setup RC tag name for future development builds on this release branch
	future_rc_version="${major}.${minor}.${patch}"
	if [[ "$release_type" == "final" ]]; then
		rc="1"
	else
		((rc++))
	fi	

	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == "final" ]]; then
			future_rc_qualifier="-HF1-RC$rc-SNAPSHOT"
		else 
			future_rc_qualifier="-RC$rc-SNAPSHOT"
		fi	
	else
		if [[ "$release_type" == "final" ]]; then
			((hf++))
		fi
		future_rc_qualifier="-HF$hf-RC$rc-SNAPSHOT"
	fi
	echo "1. will work on branch $branch_name"

	# Update the Maven version in the maven.config file
	updateMavenConfig "$new_rc_version" "$new_rc_qualifier"
	#sed -i "s/-Drevision=.*/-Drevision=$new_rc_version/" .mvn/maven.config
	#sed -i "s/-Dchangelist=.*/-Dchangelist=$new_rc_qualifier/" .mvn/maven.config
	echo "2. will update .mvn/maven.config on branch to $new_rc_version and $new_rc_qualifier"

	git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
	git tag "$new_rc_version$new_rc_qualifier" "$branch_name"
	echo "3. will commit the .mvn/maven.config changes and  create a tag $new_rc_version$new_rc_qualifier to branch: $branch_name"

	# Build goes here
	#
	#
	echo "4. Build goes here"

	if [[ "$release_type" == "final" ]]; then
		echo "4.1 This a final release build, the result should go on some SERVER here" 
	fi

	# Update the Maven version in the maven.config file for future RC builds
	updateMavenConfig "$future_rc_version" "$future_rc_qualifier"
	#sed -i "s/-Drevision=.*/-Drevision=$future_rc_version/" .mvn/maven.config
	#sed -i "s/-Dchangelist=.*/-Dchangelist=$future_rc_qualifier/" .mvn/maven.config
	echo "5. will update .mvn/maven.config on branch $branch_name to $future_rc_version and $future_rc_qualifier"

	git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of version" .mvn/maven.config
	git tag "$future_rc_version$future_rc_qualifier" "$branch_name"
	echo "6. will commit the .mvn/maven.config changes and  create a tag $future_rc_version$future_rc_qualifier" 

	git push --tags #not recommended
	git push
	echo "7. will push the new maven version and tags to $branch_name"
}