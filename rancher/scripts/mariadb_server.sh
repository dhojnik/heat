#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)

source /etc/profile.d/proxy.sh

yum clean all

# Configure MariaDB Storage

if [[ ! -d /var/lib/mysql ]]; then
    mkdir /var/lib/mysql
fi

if [[ -e /dev/sdb ]] && [[ ! -e /dev/sdb1 ]]; then
    parted /dev/sdb mklabel gpt
    parted -s -a optimal /dev/sdb mkpart primary 0% 100%
    mkfs.xfs -n ftype=1 /dev/sdb1
    echo -e "/dev/sdb1                                 /var/lib/mysql          xfs     defaults        0 0" >> /etc/fstab
    mount -a
fi

# Disable unneeded services

systemctl disable auditd.service

# Install MariaDB

yum -y install mariadb-server

cat << HERE > /etc/my.cnf.d/mariadb.cnf
[mysqld]
open_files_limit = 8192
max_connections = 8192
bind-address = ${IPADDR}
default-storage-engine = innodb
innodb_file_per_table
collation-server = utf8_general_ci
init-connect = 'SET NAMES utf8'
character-set-server = utf8
HERE

mkdir /etc/systemd/system/mariadb.service.d

cat << HERE > /etc/systemd/system/mariadb.service.d/limits.conf
[Service]
LimitNOFILE=8192
LimitMEMLOCK=8192
HERE

systemctl enable mariadb && systemctl start mariadb

sleep 10

mysql -u root <<-EOF
GRANT ALL ON *.* TO 'dbadmin'@'%' IDENTIFIED BY '$MARIADB_DBADMIN_PASSWORD';
GRANT ALL ON *.* TO 'dbadmin'@'localhost' IDENTIFIED BY '$MARIADB_DBADMIN_PASSWORD';
UPDATE mysql.user SET Password=PASSWORD('$MARIADB_ROOT_PASSWORD') WHERE User='root';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
CREATE DATABASE IF NOT EXISTS cattle COLLATE = 'utf8_general_ci' CHARACTER SET = 'utf8';
GRANT ALL PRIVILEGES ON cattle.* TO 'cattle'@'%' IDENTIFIED BY '$MARIADB_RANCHER_PASSWORD';
FLUSH PRIVILEGES;
EOF

systemctl stop os-collect-config
systemctl disable os-collect-config

systemctl restart mariadb

sleep 10

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

echo "The installation is complete."

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

echo "MARIADB_DBADMIN_PASSWORD=$MARIADB_DBADMIN_PASSWORD"
echo "MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD"
echo "MARIADB_RANCHER_PASSWORD=$MARIADB_RANCHER_PASSWORD"
