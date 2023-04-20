#!/bin/bash

#Globals
MASTER_BRANCH="master"
DEBUG=true

#PATHS
CLIENT_LOCATION="gemma-client"
HELM_CHARTS_LOCATION="charts"
MAVEN_VERSION_FILE=".mvn/maven.config"
HELM_CHARTS_VERSION_FILE="${HELM_CHARTS_LOCATION}/project/Chart.yaml"
HELM_CHARTS_VERSION_FILE_keycloak="${HELM_CHARTS_LOCATION}/project-1/Chart.yaml"
HELM_CHARTS_VERSION_FILE_keycloak_operator="${HELM_CHARTS_LOCATION}/project-2/Chart.yaml"
HELM_CHARTS_VERSION_FILE_keycloak_theme="${HELM_CHARTS_LOCATION}/project-3/Chart.yaml"
CLIENT_VERSION_FILE="${CLIENT_LOCATION}/package.json"

#REGEX
TAG_FORMAT_ON_MASTER="^[0-9]*+\.[0-9]*+\.[0-9]*+-SNAPSHOT$"
TAG_FORMAT_SNAPSHOT_RC="^[0-9]*+\.[0-9]*+\.[0-9]*+-((HF[0-9]+-RC[0-9]+)|(RC[0-9]+))-SNAPSHOT$"
TAG_PATTERN_ON_MASTER="([0-9]+)\.([0-9]+)\.([0-9]+)-SNAPSHOT"
TAG_PATTERN_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)$"
TAG_PATTERN_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)$"
TAG_PATTERN_FINAL_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)$"
TAG_PATTERN_FINAL_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)$"
TAG_PATTERN_SNAPSHOT_RELEASE="^([0-9]+)\.([0-9]+)\.([0-9]+)-RC([0-9]+)-SNAPSHOT$"
TAG_PATTERN_SNAPSHOT_HOTFIX="^([0-9]+)\.([0-9]+)\.([0-9]+)-HF([0-9]+)-RC([0-9]+)-SNAPSHOT$"
BRANCH_PATTERN="^VERSION-([0-9]+)\.([0-9]+)\.([0-9]+)$"

# General
LOG() {
	if [[ "$1" = "-d" && "$DEBUG" = "true" ]];
	then
		echo `date` "[DEBUG]"  "$2" 
	elif [ "$1" = "-e" ];
	then
		echo `date` "[ERROR]"  "$2"
	else		
		echo `date` "[INFO]"  "$1"
	fi
}

# Git related 
configure_git_committer() {
	local -r user_name=${1}
	local -r user_email=${2}
	git config user.name "${user_name}"
	git config user.email "${user_email}"
}
 
runningOnMaster() {
	current_branch=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $current_branch =~ ^$MASTER_BRANCH$ ]]; then		
		return 1
	fi
	return 0
}

branchExists() {
	if [ $# -ne 1 ]; then
		LOG -e "branchExists() - Invalid number of parameters provided. Expected 1, received $#."
		return 1
	fi
	branch=$1
	if git ls-remote --exit-code --heads origin $BRANCH >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

tagExists() {
	if [ $# -ne 1 ]; then
		LOG -e "tagExists() - Invalid number of parameters provided. Expected 1, received $#."
		return 1
	fi
	TAG=$1
	if git ls-remote --exit-code --tags --heads origin refs/tags/$TAG >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

# Version related
isVersionReady() {
	ON_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	
	if [ $# -ne 2 ]; then
		LOG -e "isVersionReady() - Invalid number of parameters provided. Expected 2, received $#."
		return 1
	fi
	version=$1
	qualifier=$2	
			
	maven_revision=$(get_maven_revision)
	maven_qualifier=$(get_maven_qualifier)	
	helm_chart=$(get_helm_chart_version $ON_BRANCH)
	client_version=$(get_client_version $ON_BRANCH)
	
	if [[ "$maven_revision" == "$version" && "$maven_qualifier" == "$qualifier" &&
		"$helm_chart" == "$version$maven_qualifier" && "$client_version" == "$version$maven_qualifier" ]]; then 
		return 0
	fi
	
	return 1	
}

updateMavenConfig() {
	if [ $# -ne 2 ]; then
		LOG -e "updateMavenConfig() - Invalid number of parameters provided. Expected 2, received $#."
		return 1
	fi
	version=$1
	qualifier=$2	
	sed -i "s/-Drevision=.*/-Drevision=$version/" $MAVEN_VERSION_FILE
	sed -i "s/-Dchangelist=.*/-Dchangelist=$qualifier/" $MAVEN_VERSION_FILE
	return 0
}

get_maven_revision() {
	revision="$(grep revision $MAVEN_VERSION_FILE | sed 's/-Drevision=//')"
	echo $revision
}

get_maven_revision_on_branch() {
	ON_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	
	# Get the branch name. Check if the argument exists
	if [ -z "$1" ]; then
    	LOG -e "Branch argument is missing"
		exit 1
	else
    	branch_name="$1"
	fi
	
	git checkout $branch_name >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $branch_name"; exit 1; }
	
	revision="$(get_maven_revision)"
	
	# return to initial branch
	git checkout $ON_BRANCH >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $ON_BRANCH"; exit 1; }
	
	echo $revision
}

get_maven_qualifier() {
	qualifier="$(grep changelist $MAVEN_VERSION_FILE | sed 's/-Dchangelist=//')"
	echo $qualifier
}

get_maven_qualifier_on_branch() {
	ON_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	
	# Get the branch name. Check if the argument exists
	if [ -z "$1" ]; then
    	LOG -e "Branch argument is missing"
		exit 1
	else
    	branch_name="$1"
	fi
	
	git checkout $branch_name >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $branch_name"; exit 1; }
	
	qualifier="$(get_maven_qualifier)"
	
	# return to initial branch
	git checkout $ON_BRANCH >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $ON_BRANCH"; exit 1; }
	
	echo $qualifier
}


set_helm_chart_version() {
	if [ $# -lt 1 ]; then
			LOG -e "set_helm_chart_version() - Invalid number of parameters provided. Expected at least 1, received $#."
			return 1
	fi
	if [ -z "$2" ]; then
		commit=true
	else		
		if [[ "$2" == "no-commit" ]]; then
			commit=false
			LOG -d "set_helm_chart_version(): Version file will be updated. Commit will be skipped."
		fi
	fi

	local -r version="${1}"

	version_set=0
	if ! yq  -i e ".version = \"${version}\"" $HELM_CHARTS_VERSION_FILE; then
		LOG -e "Failed to set helm chart version to ${version} - file: $HELM_CHARTS_VERSION_FILE"
		version_set=1
	fi
	if ! yq  -i e ".version = \"${version}\"" $HELM_CHARTS_VERSION_FILE_keycloak; then
		LOG -e "Failed to set helm chart version to ${version} - file: $HELM_CHARTS_VERSION_FILE_keycloak"
		version_set=1
	fi
	if ! yq  -i e ".version = \"${version}\"" $HELM_CHARTS_VERSION_FILE_keycloak_operator; then
		LOG -e "Failed to set helm chart version to ${version} - file: $HELM_CHARTS_VERSION_FILE_keycloak_operator"
		version_set=1
	fi
	if ! yq  -i e ".version = \"${version}\"" $HELM_CHARTS_VERSION_FILE_keycloak_theme; then
		LOG -e "Failed to set helm chart version to ${version} - file: $HELM_CHARTS_VERSION_FILE_keycloak_theme"
		version_set=1
	fi

	if [[ "$version_set" != "0" ]]; then
		return $version_set
  	fi

	if [[ "$commit" != "false" ]]; then
		LOG -d "set_helm_chart_version() - Commit feature is disabled inside the function"
		# git commit -m "[WF] Automatic update of Helm Charts to ${version}" $HELM_CHARTS_VERSION_FILE
	fi
	
	return 0
}

get_helm_chart_version() {
	ON_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	
	# Get the branch name. Check if the argument exists
	if [ -z "$1" ]; then
    	LOG -e "Branch argument is missing"
		exit 1
	else
    	branch_name="$1"
	fi
	
	git checkout $branch_name >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $branch_name"; exit 1; }

	version=$(yq e '.version' $HELM_CHARTS_VERSION_FILE)
	
	# return to initial branch
	git checkout $ON_BRANCH >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $ON_BRANCH"; exit 1; }
	
	echo "$version"
}

set_client_version() {
	if [ $# -lt 1 ]; then
		LOG -e "set_client_version() - Invalid number of parameters provided. Expected 1, received $#."
		return 1
  	fi
	if [ -z "$2" ]; then
		commit=true
	else		
		if [[ "$2" == "no-commit" ]]; then
			commit=false
			LOG -d "set_client_version(): Version file will be updated. Commit will be skipped."
		fi
	fi

	local -r version="${1}"

	if ! yq -o=json -i e ".version = \"${version}\"" $CLIENT_VERSION_FILE; then
		LOG -e "Failed to set version for the Client project"
		return 1	
  	fi

	if [[ "$commit" != "false" ]]; then
		LOG -d "set_client_version() - Commit feature is disabled inside the function"
		#git commit -m "[WF] Automatic update of Client Project to ${version}" $CLIENT_VERSION_FILE
	fi

	return 0
}

get_client_version() {
	ON_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	
	# Get the branch name. Check if the argument exists
	if [ -z "$1" ]; then
    	LOG -e "Branch argument is missing"
		exit 1
	else
    	branch_name="$1"
	fi
	
	git checkout $branch_name >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $branch_name"; exit 1; }
	
	version=$(yq e '.version' $CLIENT_VERSION_FILE)
	
	# return to initial branch
	git checkout $ON_BRANCH >/dev/null 2>&1 ||
		{ LOG -e "Failed to checkout $ON_BRANCH"; exit 1; }
	
	echo "$version"
}

get_timestamp() {
	current_date=$(date +'%Y%m%d-%H%M%S')
	echo "$current_date"
}

grep_version_files() {
	ON_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	LOG -d "Retrieving version files from $ON_BRANCH: "
	LOG -d "	Maven revision: "$(grep "revision" $MAVEN_VERSION_FILE)
	LOG -d "	Maven qualifier: "$(grep "changelist" $MAVEN_VERSION_FILE)
	LOG -d "	Helm charts: "$(yq e '.version' $HELM_CHARTS_VERSION_FILE)
	LOG -d "	Helm charts(_keycloak): "$(yq e '.version' $HELM_CHARTS_VERSION_FILE_keycloak)
	LOG -d "	Helm charts(_keycloak_operator): "$(yq e '.version' $HELM_CHARTS_VERSION_FILE_keycloak_operator)
	LOG -d "	Helm charts(_keycloak_theme): "$(yq e '.version' $HELM_CHARTS_VERSION_FILE_keycloak_theme)
	LOG -d "	Client: "$(yq e '.version' $CLIENT_VERSION_FILE)
}