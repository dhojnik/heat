#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)
export SUBNET=$(echo $IPADDR | cut -d '.' -f1,2,3)

printf -v subnet_ip_list '%s,' ${SUBNET}.{1..255}

cat << HERE > /etc/profile.d/proxy.sh
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export no_proxy="127.0.0.1,localhost,169.254.169.254,10.199.51.151,docker-registry,${subnet_ip_list%,}"
HERE

source /etc/profile.d/proxy.sh

yum clean all
yum makecache

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
HERE

cat << HERE > /etc/systemd/system/docker.service.d/50-http-proxy.conf
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=docker-registry"
HERE

# Configure Registry certs

echo "$REGISTRY_CA_CERT" > /docker/certs/${COMMON_NAME}-ca.pem
chmod 0400 /docker/certs/${COMMON_NAME}-ca.pem
cp -a /docker/certs/${COMMON_NAME}-ca.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust

systemctl enable docker
systemctl start docker

sleep 3

# Configure Kubernetes

cat << HERE > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
HERE

yum -y install kubelet kubeadm kubectl kubernetes-cni

systemctl enable kubelet && systemctl start kubelet

sleep 10

kubeadm init --token=$K8S_TOKEN --skip-preflight-checks

sleep 30

# Install Canal Networking
kubectl create -f https://raw.githubusercontent.com/tigera/canal/master/k8s-install/kubeadm/canal.yaml

# Install Dashboard
kubectl create -f https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

echo "The installation is complete."

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

cat /docker/certs/${COMMON_NAME}-ca.pem
