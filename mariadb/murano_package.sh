#!/bin/bash

mkdir -p Resources/HotEnvironments
mkdir -p Resources/HotFiles/fragments
mkdir -p Resources/HotFiles/scripts

rsync -a mariadb_server.yaml Resources/HotFiles/mariadb_server.yaml
rsync -a fragments/ Resources/HotFiles/fragments/
rsync -a scripts/ Resources/HotFiles/scripts/
rsync -a environments/ Resources/HotEnvironments/

murano package-create --template mariadb_cluster.yaml \
   --name 'MySQL Galera Cluster' \
   --type Application \
   --description "3 node MariaDB Galera cluster" \
   --author 'Mehmet Tecer' \
   --resources-dir 'Resources/' \
   --logo logo.png

zipinfo  mariadb_cluster.zip

murano package-import --categories Databases --is-public  mariadb_cluster.zip
