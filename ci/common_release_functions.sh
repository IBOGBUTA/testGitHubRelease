#!/bin/bash

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
		echo LOG -e "branchExists() - Invalid number of parameters provided. Expected 1, received $#."
		return 1
	fi
	branch=$1
	if git ls-remote --exit-code --heads origin $BRANCH >/dev/null 2>&1; then
		return 1
	fi
	return 0
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