#!/bin/bash

user="root"
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
  password=''
else
  password="--password=${MYSQL_ROOT_PASSWORD}"
fi
port="-P ${MYSQL_PORT:-3306}"
mysql_connect="-u $user $password $port"
mysql="mysql $mysql_connect"

if [ -z "${ENSEMBL_CONTAINER}" ]; then
  local=""
else
  local="--local"
fi

# Find the name of the database we've been given. We could have either dbname.sql.gz or dbname.mysql40_compatible.sql.gz
for sqlf in *.sql.gz; do
  if [[ "$sqlf" != *"mysql40_compatible" ]]; then
    sqlfile=$sqlf
  fi
done

if [ -z "$sqlfile" ]; then
  echo 'Cannot find a compatible SQL file. Cannot continue'
  exit 1
fi

# DB name is the name of the SQL file. Holding directories have not consistently kept their database names
dbname=${sqlfile%.*.*}

echo '!!!!!! Working with database '$dbname
echo
# Drop database first (if exists), create and squirt in the SQL
$mysql -e "drop database if exists \`${dbname}\`"
$mysql -e "create database \`${dbname}\`"
gzip -dc $sqlfile | $mysql $dbname

# Load flat files now
for gz_file in *.txt*gz; do
  file=${gz_file%.gz}
  # Sometimes files have .table.gz in their extensions so we remove it
  file=${file%.table}
  table=${file%.txt}
  echo 'Working with table '${table}
  echo -n "    Gunzipping ${table} data from file ${gz_file} into ${file} ... "
  # If we are in a container then decompress and then load
  if [ -n "${ENSEMBL_CONTAINER}" ]; then
    gzip -dc $gz_file > $file
  # Otherwise make a named pipe and write out in a sub-process
  else
    mkfifo ${file}
    gzip -dc $gz_file > $file &
  fi
  echo "Done"
  echo "ALTER TABLE \`${table}\` DISABLE KEYS" | $mysql $dbname
  mysqlimport $mysql_connect ${local} --delete $dbname ${file}
  echo "ALTER TABLE \`${table}\` ENABLE KEYS" | $mysql $dbname
  if [ -f $file ]; then
    rm $file
  fi
  echo '    Finished and removed temporary file '$file
done

echo
echo '!!!!!! Database has been loaded'
