#!/bin/bash -x

{
export IPADDR=$(ip -o -4 addr show eth0 | awk '{ print $4 }' | cut -d/ -f1)
export PROXY_URL=$PROXY_URL

source /etc/profile.d/proxy.sh
export no_proxy=$no_proxy,$IPADDR

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

# Install Mariadb Galera

yum -y install haproxy mariadb-galera-server

cat << HERE > /etc/my.cnf.d/galera.cnf
[mysqld]
open_files_limit = 8192
max_connections = 8192
bind-address = ${IPADDR}
default-storage-engine = innodb
innodb_file_per_table
collation-server = utf8_general_ci
init-connect = 'SET NAMES utf8'
character-set-server = utf8
innodb_autoinc_lock_mode = 2
binlog_format = row
port = 4306

wsrep_on = 1
wsrep_provider = /usr/lib64/galera/libgalera_smm.so
wsrep_slave_threads = 1
wsrep_certify_nonPK = 1
wsrep_max_ws_rows = 131072
wsrep_max_ws_size = 1073741824
wsrep_debug = 0
wsrep_convert_LOCK_to_trx = 0
wsrep_retry_autocommit = 1
wsrep_auto_increment_control = 1
wsrep_drupal_282555_workaround = 0
wsrep_causal_reads = 0
wsrep_notify_cmd =

wsrep_cluster_name = "mariadb_cluster"
# wsrep_node_name = 'localhost'
# wsrep_node_address = 127.0.0.1

wsrep_sst_method = rsync
wsrep_sst_auth = galera_admin:$MARIADB_GALERA_PASSWORD
HERE

if [[ "${IPADDR}" == "$SERVER01_IP" ]]; then
cat << HERE > /etc/my.cnf.d/cluster_address.cnf
[mysqld]
wsrep_cluster_address=gcomm://
HERE
else
cat << HERE > /etc/my.cnf.d/cluster_address.cnf
[mysqld]
wsrep_cluster_address=gcomm://$SERVER01_IP,$SERVER02_IP,$SERVER03_IP
HERE
fi

# Configure limits

cat << HERE > /etc/security/limits.d/mysql.conf
mysql           soft    nofile         8192
mysql           hard    nofile         8192
HERE

mkdir /etc/systemd/system/mariadb.service.d

cat << HERE > /etc/systemd/system/mariadb.service.d/limits.conf
[Service]
LimitNOFILE=8192
LimitMEMLOCK=8192
HERE

systemctl enable mariadb && systemctl start mariadb

sleep 10

# Bootstrap MariaDB Galera cluster

if [[ "${IPADDR}" == "$SERVER01_IP" ]]; then
mysql -u root <<-EOF
GRANT ALL PRIVILEGES ON *.* TO 'galera_admin'@'%' IDENTIFIED BY '$MARIADB_GALERA_PASSWORD' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'dbadmin'@'%' IDENTIFIED BY '$MARIADB_DBADMIN_PASSWORD' WITH GRANT OPTION;
CREATE USER 'haproxy'@'%';
UPDATE mysql.user SET Password=PASSWORD('$MARIADB_ROOT_PASSWORD') WHERE User='root';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF

cat << HERE > /etc/my.cnf.d/cluster_address.cnf
[mysqld]
wsrep_cluster_address=gcomm://$SERVER01_IP,$SERVER02_IP,$SERVER03_IP
HERE

fi

cat << HERE > /etc/haproxy/haproxy.cfg
global
    log 127.0.0.1 local2 notice
    chroot /var/lib/haproxy
    pidfile /var/run/haproxy.pid
    maxconn 4000
    user haproxy
    group haproxy
    daemon
    stats socket /var/lib/haproxy/stats

defaults
    log global
    option  dontlognull
    option  redispatch
    retries 3
    timeout connect 3s
    timeout server 5s
    timeout client 5s

listen mariadb_cluster 0.0.0.0:3306
    mode tcp
    balance leastconn
    option tcpka
    option tcp-check
    option mysql-check user haproxy
    server mariadb01 $SERVER01_IP:4306 check port 4306 inter 12s rise 3 fall 3 weight 1
    server mariadb02 $SERVER02_IP:4306 check port 4306 inter 12s rise 3 fall 3 weight 1
    server mariadb03 $SERVER03_IP:4306 check port 4306 inter 12s rise 3 fall 3 weight 1

listen stats 0.0.0.0:9000
  mode http
  stats enable
  stats uri /haproxy_stats
  stats realm HAProxy\ Statistics
  stats auth haproxy:$MARIADB_HAPROXY_PASSWORD
  stats admin if TRUE
HERE

systemctl stop os-collect-config
systemctl disable os-collect-config

systemctl enable haproxy && systemctl start haproxy

sleep 10

$WC_NOTIFY --data-binary '{"status": "SUCCESS", "data": "Server Installation is Complete"}'

echo "The installation is complete."

} > >(tee /var/log/heat-deployment-$$.log | logger -t user-data -s >/dev/console 2>&1) 2>&1

echo "MARIADB_GALERA_PASSWORD=$MARIADB_GALERA_PASSWORD"
echo "MARIADB_DBADMIN_PASSWORD=$MARIADB_DBADMIN_PASSWORD"
echo "MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD"
