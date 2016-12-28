#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)

source /etc/profile.d/proxy.sh

yum clean all

# Configure Docker Storage

if [[ ! -d /docker ]]; then
    mkdir -p /docker
fi

if [[ -e /dev/sdb ]] && [[ ! -e /dev/sdb1 ]]; then
    parted /dev/sdb mklabel gpt
    parted -s -a optimal /dev/sdb mkpart primary 0% 100%
    mkfs.xfs -n ftype=1 /dev/sdb1
    echo -e "/dev/sdb1                                 /docker          xfs     defaults        1 2" >> /etc/fstab
    mount -a && mkdir -p /docker/certs
fi

# Install Latest Docker Engine

export COMMON_NAME="docker-registry"

echo "$REGISTRY_IP  ${COMMON_NAME}" >> /etc/hosts

cat << HERE > /etc/yum.repos.d/docker.repo
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
HERE

yum -y install docker-engine

mkdir -p /etc/systemd/system/docker.service.d

cat << HERE > /etc/systemd/system/docker.service.d/docker.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --selinux-enabled=false --log-driver=journald --storage-driver=overlay2 --graph=/docker --registry-mirror=https://docker-registry:5000
# ExecStart=/usr/bin/dockerd --selinux-enabled=false --log-driver=journald --storage-driver=overlay2 --graph=/docker --insecure-registry docker-registry:5000
HERE

cat << HERE > /etc/systemd/system/docker.service.d/50-http-proxy.conf
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=docker-registry"
HERE

echo "$REGISTRY_CA_CERT" > /docker/certs/${COMMON_NAME}-ca.pem
chmod 0400 /docker/certs/${COMMON_NAME}-ca.pem
cp -a /docker/certs/${COMMON_NAME}-ca.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust

systemctl enable docker
systemctl start docker

sleep 3

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

echo "The installation is complete."

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

cat /docker/certs/${COMMON_NAME}-ca.pem
