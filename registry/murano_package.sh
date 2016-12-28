#!/bin/bash

mkdir -p Resources/HotEnvironments
mkdir -p Resources/HotFiles/fragments
mkdir -p Resources/HotFiles/scripts

rsync -a registry_node.yaml Resources/HotFiles/registry_node.yaml
rsync -a docker_node.yaml Resources/HotFiles/docker_node.yaml

rsync -a --exclude='*.DS_Store' fragments/ Resources/HotFiles/fragments/
rsync -a --exclude='*.DS_Store' scripts/ Resources/HotFiles/scripts/
rsync -a --exclude='*.DS_Store' environments/ Resources/HotEnvironments/

murano package-create --template registry.yaml \
    --name 'Docker Registry' \
    --type Application \
    --description "Docker caching registry:v2" \
    --author 'Mehmet Tecer' \
    --resources-dir 'Resources/' \
    --logo logo.png

zipinfo  registry.zip

murano package-import --categories Databases --is-public  registry.zip
