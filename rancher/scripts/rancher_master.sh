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
    -e no_proxy="localhost,127.0.0.1" \
    -e NO_PROXY="localhost,127.0.0.1" \
    --restart=unless-stopped -p 8080:8080 -p 9345:9345 rancher/server:$RANCHER_SERVER_VERSION \
    --db-host $RANCHER_MARIADB_SERVER \
    --db-port 3306 \
    --db-user cattle \
    --db-pass $MARIADB_RANCHER_PASSWORD \
    --db-name cattle \
    --advertise-address $IPADDR

sleep 180

until $(curl --noproxy '*' --output /dev/null --silent --head --fail $RANCHER_URL); do
  printf '.'
  sleep 5
done

cd /tmp

cat << HERE > ~/.wgetrc
use_proxy=yes
http_proxy=$PROXY_URL
HERE

export https_proxy=$PROXY_URL
cd /tmp
wget -q https://github.com/rancher/cli/releases/download/v0.4.1/rancher-linux-amd64-v0.4.1.tar.gz
tar xzvf rancher-linux-amd64-v0.4.1.tar.gz
mv rancher-v0.4.1/rancher /usr/local/bin/
chmod 0700 /usr/local/bin/rancher
rm -rf /tmp/rancher-*

curl --noproxy '*' -X POST \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  --data "{\"type\":\"apikey\", \"accountId\":\"1a1\", \"name\": \"Admin API Key\", \"description\": \"Default Admin API Key created by Heat\", \"publicValue\":\"$RANCHER_ACCESS_KEY\", \"secretValue\":\"$RANCHER_SECRET_KEY\"}" \
  "$RANCHER_URL/v1/apikeys" \
  > /dev/null

export RANCHER_URL="http://$IPADDR:8080"
rancher environment create -t kubernetes K8s-Default && sleep 3
if [[ $? == 0 ]]; then
  ENV_ID=$(rancher environment list | awk '$2 == "K8s-Default" { print $1 }')
else
  $WC_NOTIFY --data-binary '{"status": "FAILURE", "data": "Rancher: environment create failed."}'
  sleep 3
  exit
fi

curl --noproxy '*' -s \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data "{\"accessMode\":\"unrestricted\",\"name\":\"Administrator\",\"id\":null,\"type\":\"localAuthConfig\",\"enabled\":true,\"password\":\"$RANCHER_PASSWORD\",\"username\":\"$RANCHER_USERNAME\"}" \
  "$RANCHER_URL/v1/localauthconfig" \
  > /dev/null

if [[ $? == 0 ]]; then
  TOKEN=$(
    curl --noproxy '*' --fail -s \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json' \
      --data "{\"code\":\"$RANCHER_USERNAME:$RANCHER_PASSWORD\",\"authProvider\":\"localauthconfig\"}" \
      "$RANCHER_URL/v1/token" \
    | jq --raw-output --exit-status '.jwt'
  )
  if [[ $TOKEN ]]; then
    PROJECT_ID=$(
      curl --noproxy '*' --fail -s \
        -H 'Accept: application/json' \
        -H "Authorization: Bearer $TOKEN" \
        "$RANCHER_URL/v1/projects" \
      | jq --raw-output --exit-status '.data[] | select(.name == "K8s-Default").id'
    )
    if [[ $PROJECT_ID && ($PROJECT_ID == $ENV_ID) ]]; then
      REGISTRATION_TOKEN_URL=$(
        curl --noproxy '*' --fail -s \
          -H 'Content-Type: application/json' \
          -H 'Accept: application/json' \
          -H "Authorization: Bearer $TOKEN" \
          --data '{"type":"registrationToken"}' \
          "$RANCHER_URL/v1/projects/$PROJECT_ID/registrationtoken" \
        | jq --raw-output --exit-status '.links.self'
      )
      sleep 3
      if [[ $REGISTRATION_TOKEN_URL ]]; then
        RANCHER_REGISTRATION_URL=$(
        curl --noproxy '*' --fail -s \
          -H 'Accept: application/json' \
          -H "Authorization: Bearer $TOKEN" \
          "$REGISTRATION_TOKEN_URL" \
        | jq --raw-output --exit-status '.links.registrationUrl'
        )
        if [[ $RANCHER_REGISTRATION_URL ]]; then
          echo "RANCHER_REGISTRATION_URL = $RANCHER_REGISTRATION_URL"
        else
          $WC_NOTIFY --data-binary '{"status": "FAILURE", "data": "Rancher: registration url is not set."}'
          sleep 3
          exit
        fi
      else
        $WC_NOTIFY --data-binary '{"status": "FAILURE", "data": "Rancher: registration token url is not set."}'
        sleep 3
        exit
      fi
    else
      $WC_NOTIFY --data-binary '{"status": "FAILURE", "data": "Rancher: environment id is wrong."}'
      sleep 3
      exit
    fi
  else
    $WC_NOTIFY --data-binary '{"status": "FAILURE", "data": "Rancher: token generation failed."}'
    sleep 3
    exit
  fi
else
  $WC_NOTIFY --data-binary '{"status": "FAILURE", "data": "Rancher: admin user creation failed."}'
  sleep 3
  exit
fi

systemctl stop os-collect-config
systemctl disable os-collect-config

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

echo "The installation is complete."

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

echo -n $RANCHER_REGISTRATION_URL
