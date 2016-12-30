#!/bin/bash

mkdir -p Resources/HotEnvironments
mkdir -p Resources/HotFiles/fragments
mkdir -p Resources/HotFiles/scripts

# Reset environment
rm -vf ./*.zip
find Resources -type f -exec rm -vf {} \;

rsync -a registry_node.yaml Resources/HotFiles/registry_node.yaml
rsync -a docker_node.yaml Resources/HotFiles/docker_node.yaml
rsync -a k8s_master.yaml Resources/HotFiles/k8s_master.yaml

rsync -a --exclude='*.DS_Store' fragments/ Resources/HotFiles/fragments/
rsync -a --exclude='*.DS_Store' scripts/ Resources/HotFiles/scripts/
rsync -a --exclude='*.DS_Store' environments/ Resources/HotEnvironments/

murano package-create --template kubernetes.yaml \
    --name 'Kubernetes v1.5' \
    --type Application \
    --description "Kubernetes cluster v1.5" \
    --author 'Mehmet Tecer' \
    --resources-dir 'Resources/' \
    --logo logo.png

zipinfo  kubernetes.zip

#murano package-import --categories 'Containers' --is-public  kubernetes.zip
