#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)
export RANCHER_URL="http://$IPADDR:8080"

source /etc/profile.d/proxy.sh
export no_proxy=$no_proxy,$IPADDR

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

mkdir -p /rancher/{docker/registry,mysql} &&
mkdir -p /rancher/docker/registry/{data,certs} &&
chown -R 102:105 /rancher/mysql

docker pull rancher/server:$RANCHER_SERVER_VERSION | cat
docker run -d \
    -e http_proxy=$PROXY_URL \
    -e https_proxy=$PROXY_URL \
    -e no_proxy="localhost,127.0.0.1,$MASTER_IP" \
    -e NO_PROXY="localhost,127.0.0.1,$MASTER_IP" \
    --restart=unless-stopped -p 8080:8080 -p 9345:9345 rancher/server:$RANCHER_SERVER_VERSION \
    --db-host $RANCHER_MARIADB_SERVER \
    --db-port 3306 \
    --db-user cattle \
    --db-pass $MARIADB_RANCHER_PASSWORD \
    --db-name cattle \
    --advertise-address $IPADDR

cd /tmp

cat << HERE > ~/.wgetrc
use_proxy=yes
http_proxy=$PROXY_URL
HERE

export https_proxy=$PROXY_URL
cd /tmp
wget -q https://github.com/rancher/cli/releases/download/v0.4.0/rancher-linux-amd64-v0.4.0.tar.gz
tar xzvf rancher-linux-amd64-v0.4.0.tar.gz
mv rancher-v0.4.0/rancher /usr/local/bin/
chmod 0700 /usr/local/bin/rancher
rm -rf /tmp/rancher-*

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

echo "RANCHER_MASTER_IP=$MASTER_IP"
echo "RANCHER_SLAVE_IP=$IPADDR"
