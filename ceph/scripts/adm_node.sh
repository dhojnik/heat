#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)
export ETCD_URL="http://$ETCD_NODE_IP:2379"
export NETWORK=$(ip route show | grep ${IPADDR} | awk '{print $1}')

source /etc/profile.d/proxy.sh
export no_proxy=$no_proxy,$ETCD_NODE_IP
sed -i '/export no_proxy/d' /etc/profile.d/proxy.sh
echo "export no_proxy=$no_proxy" >> /etc/profile.d/proxy.sh
source /etc/profile.d/proxy.sh

yum clean all
yum makecache

# Install Ceph LTS
yum -y erase centos-release-ceph-jewel
yum -y install https://download.ceph.com/rpm-jewel/el7/noarch/ceph-release-1-1.el7.noarch.rpm
yum -y install ceph-common etcd3

# Configure etcd3

# Configure hostname -> IP Key/Value pair in etcd3
etcdctl --endpoints "${ETCD_URL}" set /adm/$(hostname) "${IPADDR}"

# Configure cephman user
useradd cephman
echo "$CEPHMAN_PASSWORD" | passwd cephman --stdin

cat << HERE > /etc/sudoers.d/cephman
Defaults:cephman !requiretty
cephman ALL = (root) NOPASSWD:ALL
HERE
chmod 0440 /etc/sudoers.d/cephman

install -o cephman -g cephman -m 0700 -d /home/cephman/.ssh

echo "$CEPH_SSH_PUB_KEY" > /home/cephman/.ssh/authorized_keys
echo "$CEPH_SSH_PUB_KEY" > /home/cephman/.ssh/id_rsa.pub
echo "$CEPH_SSH_PRI_KEY" > /home/cephman/.ssh/id_rsa

cat << HERE > /home/cephman/.ssh/config
Host *
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null
HERE

chown -R cephman.cephman /home/cephman/.ssh
chmod -R 0600 /home/cephman/.ssh/*
chmod -R 0644 /home/cephman/.ssh/id_rsa.pub

# Generate /etc/hosts from ceph node registartion in etcd
cat << HERE >/usr/local/bin/etcd-watcher.sh
#!/bin/bash

# Generate /etc/hosts from ceph node registration in etcd
all_nodes=\$(etcdctl --endpoints "${ETCD_URL}" ls --recursive --sort | grep ceph-)

echo -e "# Generated by Heat - \$(date)" > /etc/hosts
echo -e "127.0.0.1\tlocalhost" >> /etc/hosts

for node in \$all_nodes;
do
    node_hostname=\$(echo \$node | cut -d/ -f3)
    node_ip=\$(etcdctl --endpoints "${ETCD_URL}" get \$node)
    echo -e "\$node_ip\t\$node_hostname" >> /etc/hosts
done

HERE

chmod 0500 /usr/local/bin/etcd-watcher.sh
/usr/local/bin/etcd-watcher.sh

ADM_NODES="$(hostname)"
MON_NODES="$(etcdctl --endpoints "${ETCD_URL}" ls --recursive --sort /mon | cut -d/ -f3 | tr '\n' ' ')"
OSD_NODES="$(etcdctl --endpoints "${ETCD_URL}" ls --recursive --sort /osd | cut -d/ -f3 | tr '\n' ' ')"
MDS_NODES="$(etcdctl --endpoints "${ETCD_URL}" ls --recursive --sort /mds | cut -d/ -f3 | tr '\n' ' ')"

for node in $MON_NODES $OSD_NODES $MDS_NODES;
do
    su - cephman -c "ssh -q cephman@${node} sudo /usr/local/bin/etcd-watcher.sh"
done

# Configure ceph cluster
#yum -y install ceph-deploy
wget -O ceph-deploy-1.5.37-0.noarch.rpm https://github.com/mtecer/heat/blob/master/ceph/bin/ceph-deploy-1.5.37-0.noarch.rpm?raw=true
yum
yum -y localinstall ceph-deploy-1.5.37-0.noarch.rpm

cat << HERE >/usr/local/bin/install_ceph_cluster.sh
#!/bin/bash

mkdir cluster-config
cd cluster-config
ceph-deploy new ${MON_NODES}

cat << EOF >> ceph.conf
public network = ${NETWORK}
cluster network = ${NETWORK}

osd pool default size = 3
osd pool default min size = 1
osd pool default pg num = 512
osd pool default pgp num = 512

mon_osd_allow_primary_affinity = true
max_open_files = 131072
mon_pg_warn_max_per_osd = 0

# 0 for OSD
# 1 for HOST - Default
osd crush chooseleaf type = 1

[osd]
osd op threads = 16
EOF

for node in ${ADM_NODES} ${MON_NODES} ${OSD_NODES} ${MDS_NODES};
do
    ceph-deploy install --no-adjust-repos \${node}
    ceph-deploy admin \${node}
done

# Iniitialize MON nodes
ceph-deploy mon create-initial

sudo cp -a ceph.conf /etc/ceph/
sudo cp -a ceph.client.admin.keyring /etc/ceph/

# Create OSD Storage
for node in ${OSD_NODES};
do
    OSD_DISKS=\$(ceph-deploy disk list \$node 2>&1 | sed -n "s|.*/dev/\(sd[b-z]\) other, unknown|\1|p" | tr '\n' ' ')
    for disk in \$OSD_DISKS;
    do
        ceph-deploy disk zap \$node:\$disk
        sleep 2
        ceph-deploy osd create \$node:\$disk
        sleep 2
    done
done

sleep 3

ceph osd pool set rbd pg_num 256
ceph osd pool set rbd pgp_num 256

# Create MDS pool
ceph-deploy mds create ${MDS_NODES}

ceph osd pool create cephfs_data 512
ceph osd pool create cephfs_metadata 512

ceph fs new cephfs cephfs_metadata cephfs_data

HERE

chown cephman /usr/local/bin/install_ceph_cluster.sh
chmod 0500 /usr/local/bin/install_ceph_cluster.sh

su - cephman -c /usr/local/bin/install_ceph_cluster.sh

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1
