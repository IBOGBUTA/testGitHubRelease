#!/bin/bash

#Globals
HELM_CHARTS_LOCATION="charts"
CLIENT_LOCATION="project-client"

# General
LOG() {
	if [ "$1" = "-d" ];
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
runningOnMaster() {
	current_branch=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $current_branch =~ ^master$ ]]; then		
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
updateMavenConfig() {
	if [ $# -ne 2 ]; then
		LOG -e "updateMavenConfig() - Invalid number of parameters provided. Expected 2, received $#."
		return 1
	fi
	version=$1
	qualifier=$2	
	sed -i "s/-Drevision=.*/-Drevision=$version/" .mvn/maven.config
	sed -i "s/-Dchangelist=.*/-Dchangelist=$qualifier/" .mvn/maven.config
	return 0
}

set_helm_chart_version() {
	if [ $# -ne 2 ]; then
			LOG -e "set_helm_chart_version() - Invalid number of parameters provided. Expected 2, received $#."
			return 1
	fi
	if [ -z "$3" ]; then
		commit=true
	else		
		if [[ "$3" == "no-commit" ]]; then
			commit=false
			LOG -d "set_helm_chart_version(): Version file will be updated. Commit will be skipped."
		fi
	fi

	local -r chart="${1}"
	local -r version="${2}"

	if ! yq  -i e ".version = \"${version}\"" "${HELM_CHARTS_LOCATION}/${chart}/Chart.yaml"; then
		LOG -e "Failed to set helm chart version to ${version}"
		return 1
	fi

	if ! yq  -i e ".image.version = \"${version}\"" "${HELM_CHARTS_LOCATION}/${chart}/values.yaml"; then
		LOG -e "Failed to set helm chart image version to ${version}"
		return 1
	fi 

	if [[ "$commit" != "false" ]]; then
		git commit -m "[WF] Automatic update of Helm Charts to ${version}" "${HELM_CHARTS_LOCATION}/${chart}/Chart.yaml" "${HELM_CHARTS_LOCATION}/${chart}/values.yaml"
	fi
	
	return 0
}

set_client_version() {
	if [ $# -ne 1 ]; then
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

	if ! yq -i e ".version = \"${version}\"" "${CLIENT_LOCATION}/package.json"; then
		LOG -e "Failed to set version for the Client project"
		return 1	
  	fi

	if [[ "$commit" != "false" ]]; then
		git commit -m "[WF] Automatic update of Client Project to ${version}" "${CLIENT_LOCATION}/package.json"	
	fi

	return 0
}