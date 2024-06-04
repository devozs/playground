#!/bin/bash

kics_output=$(docker run -t -v ${1}:/path checkmarx/kics:latest scan -p /path/Dockerfile -o "/path/")
echo "${kics_output}"
