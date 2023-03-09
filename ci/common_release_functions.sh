#!/bin/bash

runningOnMaster() {
	current_branch=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $current_branch =~ ^master$ ]]; then		
		return 1
	fi
	return 0
}

updateMavenConfig() {
	if [ $# -ne 2 ]; then
		echo "Error: updateMavenConfig() - Invalid number of parameters provided. Expected 2, received $#."
		return 1
	fi
	version=$1
	qualifier=$2	
	sed -i "s/-Drevision=.*/-Drevision=$version/" .mvn/maven.config
	sed -i "s/-Dchangelist=.*/-Dchangelist=$qualifier/" .mvn/maven.config
	return 0
}