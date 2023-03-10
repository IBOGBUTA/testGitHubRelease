#!/bin/bash

# Description:
### This script can run only on master and it will continue on the release branch
### This is common code for Release RC and for the HF RC

RUN_PATH=$(dirname "${BASH_SOURCE[0]}")
source $RUN_PATH/common_release_functions.sh || { LOG -e "Cannot reach external resource $RUN_PATH/common_release_functions.sh. Will exit."; exit 1; }

TAG_FORMAT_SNAPSHOT_RC="^[0-9]*+\.[0-9]*+\.[0-9]*+-((HF[0-9]+-RC[0-9]+)|(RC[0-9]+))-SNAPSHOT$"
TAG_PATTERN_SNAPSHOT_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)-SNAPSHOT$"
TAG_PATTERN_SNAPSHOT_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)-SNAPSHOT$"
DEF_ARGV_FINAL="final"

## checkBranchAndRestrictions()
## This function will confirm that the provided branch exists and
## the provided restriction is matched (the upcoming build will trigger a relase build or a HF)
## accepts arguments:
## 			$1 				- branch name
##			$1(optional) 	- [hotfix | release]
## returns:
##			0 - if all checks passed
##			1 - if checks failed

function checkBranchAndRestrictions() {
	# This script can run only on master branch
	runningOnMaster || { LOG -e "checkBranchAndRestrictions() can be called only from the master branch."; exit 1; }
	
	# Get the branch name where the check should be made
	if [ -z "$1" ]; then
		LOG -e "Branch name argument is missing"
		exit 1
	else
		branch_name="$1"
	fi
	
	# Get the release type of this new candidate
	if [ -z "$2" ]; then
		restriction_type="none" 
	else
		restriction_type="$2"
		if [[ "$restriction_type" != "release" && "$restriction_type" != "hotfix" ]]; then
			LOG -e "Release type argument can be 'release', 'hotfix' or empty"
			exit 1
		fi
	fi
	
	branchExists && { LOG "Branch $branch_name exists. Script can continue."; } || { LOG -e "Branch $branch_name doesn't exist. Will exit."; return 1; }
	
	restrictionRes=0
	if [[ "$restriction_type" != "none" ]]; then
		git fetch
        git checkout $branch_name
        git fetch --tags
            
		tag=$(git for-each-ref --sort=-creatordate --format '%(refname:short)' refs/tags --merged $branch_name | grep -E $TAG_FORMAT_SNAPSHOT_RC | head -1)
		
		nextVersionType="unknown"
        if [[ $tag =~ $TAG_PATTERN_SNAPSHOT_RELEASE ]]; then
            nextVersionType="release"
			if [[ "$restriction_type" == "hotfix" ]]; then
				LOG -e "Expecting a release, but next version is a hotfix release. Is this the correct branch?"
				restrictionRes=1
			fi			
        elif [[ $tag =~ $TAG_PATTERN_SNAPSHOT_HOTFIX ]]; then
            nextVersionType="hotfix"
			if [[ "$restriction_type" == "release" ]]; then 
				LOG -e "Expecting hotfix, but next version is a release. Is this the correct branch?"
				restrictionRes=1
			fi
        else
			LOG -e "Latest tag($tag) cannot be used to determine next release type. Please correct the tags."
			restrictionRes=1			
        fi	
		#return to master
		git checkout master
	fi	
	
	return $restrictionRes
}


## getNextVersion()
## This function will provide the next possible release version or 
## will exit with return code 1 if anything fails 
## accepts arguments:
## 			$1 				- branch name
##			$2(optional) 	- final or empty
## returns: 
##			0 - in case of success
##	   string - representing the next release version
function getNextVersion() {
	# This script can run only on master branch
	runningOnMaster || { LOG -e "getNextVersion() can be called only from the master branch."; exit 1; }
	
	# Get the branch name where the new RC will be built
	if [ -z "$1" ]; then
		LOG -e "Branch name argument is missing"
		exit 1
	else
		branch_name="$1"
	fi
	
	# Get the release type of this new candidate
	if [ -z "$2" ]; then
		release_type="rc" #set to a value that will not be used
	else
		release_type="$2"
		if [[ "$release_type" != $DEF_ARGV_FINAL ]]; then
			LOG -e "Release type argument can be empty or 'final'"
			exit 1
		fi
	fi
	
	#switch to the release branch and continue
	git fetch >/dev/null 2>&1
	git checkout $branch_name >/dev/null 2>&1
	
	# Check if the previous tag follows the format X.Y.Z(-HFN)-RCN-SNAPSHOT
	# get the latest tag
	git fetch --tags >/dev/null 2>&1
	
	# Retrieve latest tag on current branch that matches the format X.Y.Z-RCN-SNAPSHOT or X.Y.Z-HFN-RCN-SNAPSHOT
	tag=$(git for-each-ref --sort=-creatordate --format '%(refname:short)' refs/tags --merged $branch_name | grep -E $TAG_FORMAT_SNAPSHOT_RC | head -1)
	
	isHF=false
	# get the major, minor, patch, RC and HF on else branch 
	if [[ $tag =~ $TAG_PATTERN_SNAPSHOT_RELEASE ]]; then
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		rc=${BASH_REMATCH[4]}
	elif [[ $tag =~ $TAG_PATTERN_SNAPSHOT_HOTFIX ]]; then
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}
		rc=${BASH_REMATCH[5]}
		isHF=true;
	else
		LOG -e "tag ($tag) is not in the correct format" >&2
		exit 1
	fi
	
	# Setup RC tag for the upcoming build
	new_rc_version="${major}.${minor}.${patch}"
	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == $DEF_ARGV_FINAL ]]; then
			new_rc_qualifier=""
		else
			new_rc_qualifier="-RC$rc"
		fi
	else
		if [[ "$release_type" == $DEF_ARGV_FINAL ]]; then
			new_rc_qualifier="-HF$hf"
		else
			new_rc_qualifier="-HF$hf-RC$rc"
		fi
	fi
	
	#Do not use LOG here, this is the string returned by the function
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