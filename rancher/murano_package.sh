#!/bin/bash

mkdir -p Resources/HotEnvironments
mkdir -p Resources/HotFiles/fragments
mkdir -p Resources/HotFiles/scripts

rsync -a mariadb_server.yaml Resources/HotFiles/mariadb_server.yaml
rsync -a rancher_server.yaml Resources/HotFiles/rancher_server.yaml
rsync -a rancher_agent.yaml Resources/HotFiles/rancher_agent.yaml

rsync -a --exclude='*.DS_Store' fragments/ Resources/HotFiles/fragments/
rsync -a --exclude='*.DS_Store' scripts/ Resources/HotFiles/scripts/
rsync -a --exclude='*.DS_Store' environments/ Resources/HotEnvironments/

murano package-create --template rancher_cluster.yaml \
    --name 'Rancher & Kubernetes' \
    --type Application \
    --description "Kubernetes cluster on Rancher" \
    --author 'Mehmet Tecer' \
    --resources-dir 'Resources/' \
    --logo logo.png

 zipinfo  rancher_cluster.zip

 murano package-import --categories Databases --is-public  mariadb_cluster.zip
