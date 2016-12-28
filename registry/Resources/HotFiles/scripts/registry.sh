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

# Configure Registry Storage

if [[ ! -d /registry ]]; then
    mkdir -p /registry
fi

if [[ -e /dev/sdc ]] && [[ ! -e /dev/sdc1 ]]; then
    parted /dev/sdc mklabel gpt
    parted -s -a optimal /dev/sdc mkpart primary 0% 100%
    mkfs.xfs -n ftype=1 /dev/sdc1
    echo -e "/dev/sdc1                                 /registry          xfs     defaults        1 2" >> /etc/fstab
    mount -a && mkdir -p /registry/{ca,certs,data}
fi

# Install Latest Docker Engine

export COMMON_NAME="docker-registry"

echo "${REGISTRY_IP:-$IPADDR}  docker-registry" >> /etc/hosts

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
ExecStart=/usr/bin/dockerd --selinux-enabled=false --log-driver=journald --storage-driver=overlay2 --graph=/docker
HERE

cat << HERE > /etc/systemd/system/docker.service.d/50-http-proxy.conf
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=docker-registry"
HERE

# Configure Registry

cd /registry/ca

cat << HERE > openssl.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = docker-registry
IP.1 = ${IPADDR}
# IP.2 = 10.199.54.19
# IP.3 = 10.199.55.100
# DNS.2 = docker-registry.default
# DNS.3 = \${MASTER_DNS_NAME}
# IP.4 = \${MASTER_IP}
# IP. = \${MASTER_LOADBALANCER_IP}
HERE

openssl genrsa -out ca-key.pem 2048
openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=registry-ca"

openssl genrsa -out ${COMMON_NAME}-key.pem 2048
openssl req -new -key ${COMMON_NAME}-key.pem -out ${COMMON_NAME}.csr -subj "/CN=${COMMON_NAME}" -config openssl.cnf
openssl x509 -req -in ${COMMON_NAME}.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out ${COMMON_NAME}.pem -days 3650 -extensions v3_req -extfile openssl.cnf

chmod 400 ${COMMON_NAME}*.pem

rsync -a ${COMMON_NAME}*.pem ../certs/

cd /etc/pki/ca-trust/source/anchors/
cp -a /registry/ca/ca.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust

systemctl enable docker
systemctl start docker

sleep 3

docker pull registry:2
docker run -d -p 5000:5000 --restart=always --name registry \
    -v /registry/data:/var/lib/registry \
    -v /registry/certs:/certs \
    -e http_proxy=$PROXY_URL \
    -e https_proxy=$PROXY_URL \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/docker-registry.pem \
    -e REGISTRY_HTTP_TLS_KEY=/certs/docker-registry-key.pem \
    -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
    registry:2

sleep 10

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

echo "The installation is complete."

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

# echo -n $RANCHER_REGISTRATION_URL

cat /registry/ca/ca.pem
