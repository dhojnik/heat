#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)
export ETCD_URL="http://${IPADDR}:2379"

source /etc/profile.d/proxy.sh
export no_proxy=$no_proxy,${IPADDR}
sed -i '/export no_proxy/d' /etc/profile.d/proxy.sh
echo "export no_proxy=$no_proxy" >> /etc/profile.d/proxy.sh
source /etc/profile.d/proxy.sh

yum clean all
yum makecache

# Install etcd
yum -y erase centos-release-ceph-jewel
yum -y install etcd3

# Configure etcd3
sed -i "/ETCD_LISTEN_CLIENT_URLS/s/localhost/${IPADDR}/" /etc/etcd/etcd.conf
sed -i "/ETCD_ADVERTISE_CLIENT_URLS/s/localhost/${IPADDR}/" /etc/etcd/etcd.conf

systemctl enable etcd && systemctl start etcd

sleep 3

etcdctl --endpoints "${ETCD_URL}" mkdir /adm
etcdctl --endpoints "${ETCD_URL}" mkdir /mon
etcdctl --endpoints "${ETCD_URL}" mkdir /osd
etcdctl --endpoints "${ETCD_URL}" mkdir /mds

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1
