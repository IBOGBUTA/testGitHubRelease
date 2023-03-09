#!/bin/bash

runningOnMaster() {
	current_branch=$(git rev-parse --abbrev-ref HEAD)
	if [[ ! $current_branch =~ ^master$ ]]; then		
		return 1
	fi
	return 0
}