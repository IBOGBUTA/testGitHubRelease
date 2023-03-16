#!/bin/bash

# Description:
### This script can run only on master and it will continue on the release branch
### This is common code for Release RC and for the HF RC

RUN_PATH=$(dirname "${BASH_SOURCE[0]}")
source $RUN_PATH/common_release_functions.sh || { LOG -e "Cannot reach external resource $RUN_PATH/common_release_functions.sh. Will exit."; exit 1; }

TAG_FORMAT_SNAPSHOT_RC="^[0-9]*+\.[0-9]*+\.[0-9]*+-((HF[0-9]+-RC[0-9]+)|(RC[0-9]+))-SNAPSHOT$"
TAG_PATTERN_SNAPSHOT_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)-SNAPSHOT$"
TAG_PATTERN_SNAPSHOT_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)-SNAPSHOT$"

TAG_PATTERN_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)$"
TAG_PATTERN_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)$"
TAG_PATTERN_FINAL_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)$"
TAG_PATTERN_FINAL_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)$"

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
	
	branchExists $branch_name && { LOG "Branch $branch_name exists. Script can continue."; } || { LOG -e "Branch $branch_name doesn't exist. Will exit."; return 1; }
	
	restrictionRes=0
	if [[ "$restriction_type" != "none" ]]; then
		git fetch >/dev/null 2>&1
        git checkout $branch_name >/dev/null 2>&1
        git fetch --tags >/dev/null 2>&1
            
		tag=$(git for-each-ref --sort=-creatordate --format '%(refname:short)' refs/tags --merged $branch_name | grep -E $TAG_FORMAT_SNAPSHOT_RC | head -1)
		
		nextVersionType="unknown"
        if [[ $tag =~ $TAG_PATTERN_SNAPSHOT_RELEASE ]]; then
            nextVersionType="release"
			if [[ "$restriction_type" == "hotfix" ]]; then
				LOG -e "Expecting hotfix, but next build type on this branch is a release. Is this the correct branch?"
				restrictionRes=1
			fi			
        elif [[ $tag =~ $TAG_PATTERN_SNAPSHOT_HOTFIX ]]; then
            nextVersionType="hotfix"
			if [[ "$restriction_type" == "release" ]]; then 
				LOG -e "Expecting release, but next build type on this branch is a hotfix. Is this the correct branch?"
				restrictionRes=1
			fi
        else
			LOG -e "Latest tag($tag) cannot be used to determine next release type. Please correct the tags."
			restrictionRes=1			
        fi	
		#return to master
		git checkout master >/dev/null 2>&1	

		[[ $restrictionRes == 0 ]] && LOG "The next build will be a $restriction_type as expected."
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

## updateForNextVersion()
## This function requires as an argument the version that should be pushed and
## another(optional) one that states if the version is final or not 
## accepts arguments:
## 			$1 				- version name
##			$2(optional) 	- final or empty
## returns: 
##			0 - in case of success
function updateForNextVersion() {
	# Check if the current branch name matches the pattern master
	runningOnMaster || { LOG -e "updateForNextVersion() can be called only from the master branch."; exit 1; }
		
	# Get the version of the new build
	# Check if the argument exists
	if [ -z "$1" ]; then
    	LOG -e "Version argument is missing"
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
		if [[ "$release_type" != $DEF_ARGV_FINAL ]]; then
			LOG -e "Release type argument can be empty or 'final'"
			exit 1
		fi
	fi
	
	isHF=false
	# get the major, minor, patch, RC and HF on branch 
	if [[ $version =~ $TAG_PATTERN_RELEASE ]]; then
		LOG "Request is to build new release candidate with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		rc=${BASH_REMATCH[4]}
	elif [[ $version =~ $TAG_PATTERN_HOTFIX ]]; then
		LOG "Request is to build new HF release candidate with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}
		rc=${BASH_REMATCH[5]}
		isHF=true;
	elif [[ $version =~ $TAG_PATTERN_FINAL_RELEASE && "$release_type" == $DEF_ARGV_FINAL ]]; then
		LOG "Request is to build final release with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
	elif [[ $version =~ $TAG_PATTERN_FINAL_HOTFIX && "$release_type" == $DEF_ARGV_FINAL ]]; then
		LOG "Request is to build final HF release with version: $version"
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}		
		isHF=true;
	else
		LOG -e "Version ($version) is not in the correct format" >&2
		exit 1
	fi
	
	branch_name="VERSION-${major}.${minor}.${patch}"	
    branchExists $branch_name && { LOG "Branch $branch_name exists. Script can continue."; } || { LOG -e "Branch $branch_name doesn't exist. Will exit."; exit 1; }	
			
	git fetch >/dev/null 2>&1
	git checkout $branch_name >/dev/null 2>&1
	git fetch --tags >/dev/null 2>&1
	
	# Setup RC tag name for future development builds on this release branch
	future_rc_version="${major}.${minor}.${patch}"
	if [[ "$release_type" == $DEF_ARGV_FINAL ]]; then
		rc="1"
	else
		((rc++))
	fi	

	if [ "$isHF" == "false" ]; then
		if [[ "$release_type" == $DEF_ARGV_FINAL ]]; then
			future_rc_qualifier="-HF1-RC$rc-SNAPSHOT"
		else 
			future_rc_qualifier="-RC$rc-SNAPSHOT"
		fi	
	else
		if [[ "$release_type" == $DEF_ARGV_FINAL ]]; then
			((hf++))
		fi
		future_rc_qualifier="-HF$hf-RC$rc-SNAPSHOT"
	fi	
	
	# Update the Maven version in the maven.config file for future RC builds
	updateMavenConfig "$future_rc_version" "$future_rc_qualifier"	
	git diff --exit-code --quiet .mvn/maven.config || git commit -m "Automatic update of next version $future_rc_version$future_rc_qualifier" .mvn/maven.config
	git tag "$future_rc_version$future_rc_qualifier" "$branch_name"	
	LOG "Maven version updated to $future_rc_version$future_rc_qualifier (changed file: .mvn/maven.config)"	

	# Update Helm Charts	
	chart_version="$future_rc_version$future_rc_qualifier"
	LOG "Helm chart will be set to use version: $chart_version"
	set_helm_chart_version "project" "${chart_version}" && LOG "Helm chart set to use version: $chart_version" || exit 1
	
	# Will use the chart versioning for the client as well 
	set_client_version "${chart_version}" && LOG "Client set to use version: $chart_version" || exit 1

	git push --tags >/dev/null 2>&1
	git push >/dev/null 2>&1
}

## getPreviousReleaseTag()
## Will retieve the previous tag based on the format of the current tag
### Examples: 
### 3.0.0-RC1 is built => commits between 3.0.0-RC1-SNAPSHOT and 3.0.0-RC1
### 3.1.0-RC4 is built => commits between 3.1.0-RC1-SNAPSHOT and 3.1.0-RC4
### 3.2.0     is built => commits between 3.2.0-RC1-SNAPSHOT and 3.2.0
### 3.2.0-HF1-RC1 is built => commits between 3.2.0-HF1-RC1-SNAPSHOT and 3.2.0-HF1-RC1
### 3.2.0-HF1 is built => commits between 3.2.0-HF1-RC1-SNAPSHOT and 3.2.0-HF1
function getChangelog() {
	# Check if the current branch name matches the pattern master
	runningOnMaster || { LOG -e "getChangelog() can be called only from the master branch."; exit 1; }

	# Get the version of this recent build
	# Check if the argument exists
	if [ -z "$1" ]; then
    	LOG -e "Version argument is missing"
		exit 1
	else
    	version="$1"
	fi

	isHF=false
	# get the major, minor, patch, RC and HF on branch 
	if [[ $version =~ $TAG_PATTERN_RELEASE ]]; then		
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		rc=${BASH_REMATCH[4]}
		prev_tag=${major}.${minor}.${patch}"-RC1-SNAPSHOT"
	elif [[ $version =~ $TAG_PATTERN_HOTFIX ]]; then		
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}
		rc=${BASH_REMATCH[5]}
		prev_tag=${major}.${minor}.${patch}"-HF"$hf"-RC1-SNAPSHOT"
		isHF=true;
	elif [[ $version =~ $TAG_PATTERN_FINAL_RELEASE ]]; then
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		prev_tag=${major}.${minor}.${patch}"-RC1-SNAPSHOT"
	elif [[ $version =~ $TAG_PATTERN_FINAL_HOTFIX ]]; then
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		patch=${BASH_REMATCH[3]}
		hf=${BASH_REMATCH[4]}
		prev_tag=${major}.${minor}.${patch}"-HF"$hf"-RC1-SNAPSHOT"
		isHF=true;
	else
		LOG -e "Version ($version) is not in the correct format" >&2
		exit 1
	fi

	branch_name="VERSION-${major}.${minor}.${patch}"	
    branchExists $branch_name || { LOG -e "Branch $branch_name doesn't exist. Will exit."; exit 1; }	

	# The tags should already exist at this point, double-check here
	tagExists $version || { LOG -e "Git tag '$version' does not exists in the remote repository";exit 1; }
	tagExists $prev_tag || { LOG -e "Git tag '$prev_tag' does not exists in the remote repository";exit 1; }
	
	git fetch >/dev/null 2>&1
	git checkout $branch_name >/dev/null 2>&1
	git fetch --tags >/dev/null 2>&1
	changelog=$(git log --pretty=format:"%s" ${prev_tag}...${version} | grep -E "^\[W")
	
	git checkout master >/dev/null 2>&1

	echo "$changelog"
	return 0	
}