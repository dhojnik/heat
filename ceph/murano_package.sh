#!/bin/bash

mkdir -p Resources/HotEnvironments
mkdir -p Resources/HotFiles/fragments
mkdir -p Resources/HotFiles/scripts

# Reset environment
rm -vf ./*.zip
find Resources -type f -exec rm -vf {} \;

rsync -a ceph_cluster.yaml Resources/HotFiles/ceph_cluster.yaml
rsync -a ceph_adm_node.yaml Resources/HotFiles/ceph_adm_node.yaml
rsync -a ceph_mon_node.yaml Resources/HotFiles/ceph_mon_node.yaml
rsync -a ceph_osd_node.yaml Resources/HotFiles/ceph_osd_node.yaml
rsync -a ceph_mds_node.yaml Resources/HotFiles/ceph_mds_node.yaml
rsync -a etcd_node.yaml Resources/HotFiles/etcd_node.yaml

rsync -a --exclude='*.DS_Store' fragments/ Resources/HotFiles/fragments/
rsync -a --exclude='*.DS_Store' scripts/ Resources/HotFiles/scripts/
rsync -a --exclude='*.DS_Store' environments/ Resources/HotEnvironments/

#murano package-create --template ceph_cluster.yaml \
#    --name 'Ceph cluster' \
#    --type Application \
#    --description "Ceph cluster" \
#    --author 'Mehmet Tecer' \
#    --resources-dir 'Resources/' \
#    --logo logo.png
#
#zipinfo  ceph_cluster.zip
#
#murano package-import --categories 'Storage' --is-public  ceph_cluster.zip
