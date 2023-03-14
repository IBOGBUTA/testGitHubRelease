#!/bin/bash

RUN_PATH=$(dirname "${BASH_SOURCE[0]}")
source $RUN_PATH/common_release_functions.sh || { LOG -e "Cannot reach external resource $RUN_PATH/common_release_functions.sh. Will exit."; exit 1; }

TAG_PATTERN_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)$"
TAG_PATTERN_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)$"
TAG_PATTERN_FINAL_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)$"
TAG_PATTERN_FINAL_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)$"

DEF_ARGV_FINAL="final"

## buildNextRCPreparation()
## This function requires as an argument the version that should be built and
## its purpose is to prepare the version files for the build
## accepts arguments:
## 			$1 				- version name
##			$2(optional) 	- final or empty
## returns: 
##			0 - in case of success
function buildNextRCPreparation() {
	# Check if the current branch name matches the pattern master
	runningOnMaster || { LOG -e "buildNextRCPreparation() can be called only from the master branch."; exit 1; }
	
	# Get the version of the new build. Check if the argument exists
	if [ -z "$1" ]; then
    	LOG -e "Version argument is missing"
		exit 1
	else
    	version="$1"
	fi
	
	# Get the release type of this new candidate. Check if the second argument exists
	if [ -z "$2" ]; then
		release_type="rc"
	else
		release_type="$2"
		if [[ "$release_type" != $DEF_ARGV_FINAL ]]; then
			LOG -e "Release type argument can be empty or '$DEF_ARGV_FINAL'"
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
	
	# Setup RC tag for the build that just finished
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
	
	# Update the Maven version in the maven.config file
	updateMavenConfig "$new_rc_version" "$new_rc_qualifier"	
	LOG "Maven version updated to $new_rc_version$new_rc_qualifier (changed file: .mvn/maven.config)"	
	
	# Create the tag here, don't push
	git diff --exit-code --quiet .mvn/maven.config || git commit -m "[WF] Automatic update of version to $new_rc_version$new_rc_qualifier" .mvn/maven.config
	git tag "$new_rc_version$new_rc_qualifier" "$branch_name" >/dev/null 2>&1
	
	# Get tag commit sha
	TAG_SHA=$(git rev-parse $new_rc_version$new_rc_qualifier)	
	
	# Update Helm Charts
	current_date=$(date +'%Y%m%d.%H%M%S')
	if [[ "$release_type" == $DEF_ARGV_FINAL ]]; then
		chart_version="$new_rc_version$new_rc_qualifier"
	else
		chart_version="$new_rc_version$new_rc_qualifier-SNAPSHOT-$current_date$TAG_SHA"
	fi	
	set_helm_chart_version "project" "${chart_version}" && LOG "Helm chart set to use version: $chart_version" || exit 1
	
	# Will use the chart versioning for the client as well 
	set_client_version "${chart_version}" && LOG "Client set to use version: $chart_version" || exit 1
	
	LOG -d "Version files are ready. Build can continue."	
	return 0
}

## buildCustomVersionPreparation()
function buildCustomVersionPreparation() {

}