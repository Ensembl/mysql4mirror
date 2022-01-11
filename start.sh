#!/bin/bash
set -e
HOSTNAME=${HOSTNAME:-mysql4mirror}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-mysql4mirror}

# Only run if you are in a docker container. If we are in
# singularity we probably won't have the rights to write to /etc/hosts
# or it's a bad idea
if [ -f /.dockerenv ]; then
	if ! grep $HOSTNAME /etc/hosts >/dev/null; then
		echo "127.0.0.1 $HOSTNAME">> /etc/hosts
	fi
fi

if [ "$1" = 'mysqld_safe' ]; then
	# Again can only do if in Docker
	if [ -f /.dockerenv ]; then
		chown -R mysql:mysql /db 
	fi
		
	if  ! ls -1 /db/* 1>/dev/null 2>&1 ; then
		echo "Initializing database..."
		if [ -f /.dockerenv ]; then
			mysql_install_db --user=mysql 
		else
			mysql_install_db
		fi
       
		echo "Setting root password..."
		mysqld_safe --skip-networking &
		sleep 5
	
		#enable full network acess
		mysql --safe-updates -uroot mysql <<-EOS
SET @@SESSION.SQL_LOG_BIN=0;
DELETE FROM user where host in ('localhost','$HOSTNAME');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES ;
EOS
		sleep 5
		kill $(cat /db/*.pid)
		sleep 5
	fi
	
fi

#run it
if [ -n "$@" ]; then
	exec "$@"
fi

