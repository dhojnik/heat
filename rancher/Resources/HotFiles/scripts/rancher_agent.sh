#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)

source /etc/profile.d/proxy.sh

yum clean all

# Configure Docker Storage

if [[ ! -d /docker ]]; then
    mkdir /docker
fi

if [[ -e /dev/sdb ]] && [[ ! -e /dev/sdb1 ]]; then
    parted /dev/sdb mklabel gpt
    parted -s -a optimal /dev/sdb mkpart primary 0% 100%
    mkfs.xfs -n ftype=1 /dev/sdb1
    mount /dev/sdb1 /docker
fi

# Install Latest Docker Engine

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
ExecStart=/usr/bin/dockerd --selinux-enabled=false --log-driver=journald --storage-driver=overlay2 --graph=/docker --insecure-registry docker-registry:5000
HERE

cat << HERE > /etc/systemd/system/docker.service.d/50-http-proxy.conf
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=docker-registry"
HERE

systemctl enable docker
systemctl start docker

sleep 3

# Configure Rancher

docker pull rancher/agent:$RANCHER_AGENT_VERSION | cat
docker run -d --privileged \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/rancher:/var/lib/rancher \
    rancher/agent:$RANCHER_AGENT_VERSION \
    $RANCHER_REGISTRATION_URL

sleep 60

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

echo "The installation is complete."

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

echo "RANCHER_REGISTRATION_URL=$RANCHER_REGISTRATION_URL # $(hostname -s)"
