#!/bin/bash

/ceph-mount.sh \
	/data \
	/etc/mysql \
	/var/lib/mysql

if [ ! -e /etc/mysql/my.cnf ]; then
	cp -a /etc/mysql_dist/* /etc/mysql/
	chown -R 1000:1000 /etc/mysql
fi

if [ ! -e /data/mysql ]; then
	mkdir -p /data/mysql
	chown 1000:1000 /data
	ln -s /etc/mysql /data/mysql/config
	ln -s /var/log/mysql /data/mysql/log
	ln -s /var/lib/mysql /data/mysql/data
	chown -R 1000:1000 /data/mysql
fi

if [ ! -e /data/mysql/root_password ]; then
	pwgen -s 30 1 > /data/mysql/root_password
fi

export MYSQL_ROOT_PASSWORD=`cat /data/mysql/root_password`
echo "MySQL root password (from /data/mysql/root_password): $MYSQL_ROOT_PASSWORD"

# Upgrade MariaDB server to MariaDB Galera server
# TODO remove this block in future, it is here for smooth upgrade from older configurations
if [ ! -e /etc/mysql/galera.cfg ]; then
	echo 'Regular MariaDB server setup detected'
	gosu mysql mysqld --wsrep_on=OFF &
	while [ ! "`ps -A | grep mysqld`" ]; do
		sleep 1
	done
	sleep 3
	echo 'Upgrading to MariaDB Galera server'
	mysql_upgrade --password=$MYSQL_ROOT_PASSWORD
	pkill --signal SIGTERM mysqld
	while [ "`ps -A | grep mysqld`" ]; do
		sleep 1
	done
	echo 'Upgrading to MariaDB Galera server finished'
	sed -i 's/\/var\/lib\/mysql/&_local/g' /etc/mysql/my.cnf
	echo '!include /etc/mysql/galera.cfg' >> /etc/mysql/my.cnf
	cp /etc/mysql_dist/galera.cfg /etc/mysql/galera.cfg
	chown 1000:1000 /etc/mysql/galera.cfg
fi

# Initialize MariaDB using entrypoint from original image without last line
params_before="$@ --wsrep_sst_method=xtrabackup-v2 --wsrep_sst_auth=root:$MYSQL_ROOT_PASSWORD"
set -- $@ --bind_address=127.0.0.1 --wsrep_cluster_address=gcomm:// --wsrep_on=OFF
gosu mysql bash /docker-entrypoint-init.sh "$@"

# If this is not the master node of the service (first instance that have started) - do not use /var/lib/mysql and try to connect to the master node
service_nodes=`dig $SERVICE_NAME a +short | sort`
master_node=`cat /data/mysql/master_node_ip`
if [ ! "`echo $service_nodes | grep $master_node`" ]; then
	first_node=`echo $service_nodes | awk '{ print $1; exit }'`
	echo "Master node $master_node not reachable, changing to the first node $first_node"
	master_node=$first_node
	echo $master_node > /data/mysql/master_node_ip
fi
if [ ! "`cat /etc/hosts | grep $master_node`" ]; then
	echo "Starting as regular node (no synchronization to permanent storage)"
	if [ -L /var/lib/mysql_local ]; then
		# Change link to local directory to avoid unavoidable conflicts with master node
		rm /var/lib/mysql_local
		mkdir /tmp/mysql_local
		chown mysql:mysql /tmp/mysql_local
		ln -s /tmp/mysql_local /var/lib/mysql_local
		# Initialize MariaDB using entrypoint from original image without last line
		set -- $@ --bind_address=127.0.0.1 --wsrep_cluster_address=gcomm:// --wsrep_on=OFF
		gosu mysql bash /docker-entrypoint-init.sh "%@"
	fi
	if ! mysqladmin --host=$master_node --user=root --password=$MYSQL_ROOT_PASSWORD ping; then
		echo 'Master node is not ready, exiting'
		sleep 1
	fi
	params_before="$params_before --wsrep_cluster_address=gcomm://$master_node"
else
	echo "Starting as master node (with synchronization to permanent storage)"
	hostname > /data/mysql/master_node_hostname
	# Find other existing node to connect to
	existing_nodes=''
	for node_ip in $service_nodes; do
		if [[ "$node_ip" && "$node_ip" != "$master_node" ]]; then
			# Check if node is ready
			if mysqladmin --host=$node_ip --user=root --password=$MYSQL_ROOT_PASSWORD ping; then
				existing_nodes="$existing_nodes,$node_ip"
				break
			fi
		fi
	done
	# When first node fails to connect to any other node from the cluster, then we need to force its start
	# TODO: Ideally instances should communicate about who's version of history is more recent and then start cluster from that node,
	# but for now we assume master not to be always up to date
	if [ ! "$existing_nodes" ]; then
		echo "No existing alive nodes found in cluster, forcing start in master node"
		sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/mysql_local/grastate.dat
	fi
	params_before="$params_before --wsrep_cluster_address=gcomm://${existing_nodes:1}"
fi

set -- $params_before

if [ -e /data/mysql/before_start.sh ]; then
	bash /data/mysql/before_start.sh
else
	touch /data/mysql/before_start.sh
fi

exec gosu mysql "$@"
