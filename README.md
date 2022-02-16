# Ensembl MySQL v4 mirror

This is based on the work by [https://github.com/Tommi2Day/mysql4](https://github.com/Tommi2Day/mysql4) in building MySQL 4 deployments. This code has been modified to include additional tooling to make it easier to load and query Ensembl databases within a running instance.

# Running the container with Docker
Specify the `MYSQL_ROOT_PASSWORD` environment variable and a volume for the datafiles when launching a new container:

```sh
export LOCAL_DB_DIR=/volume1/docker/mysql
export LOCAL_FLATFILES_DIR=/volume1/docker/flatfiles
export CONTAINER_NAME=mysql4mirror
export MYSQL_ROOT_PASSWORD=mysql4mirror
export TAG=latest
docker run --name ${CONTAINER_NAME} \
--add-host="mysql4mirror:127.0.0.1" \
-e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
-v ${LOCAL_DB_DIR}:/db \
-v ${LOCAL_FLATFILES_DIR}:/flatfiles \
-p 33306:3306 \
--detach \
ensemblorg/mysql4mirror:${TAG}
```

This will run the container as a detached process, expose the MySQL on your local machine on port `33306` (within the container this will be remain `3306`), mount `/db` on the container to `/volume1/docker/mysql` locally and mount `/flatfiles` to `/volume1/docker/flatfiles` locally. You can confirm the image has started by running `docker ps`. Only one MySQL user exists on the server `root` and is set to the password you gave the container during startup.

## Opening a shell into the container

```sh
docker exec -it $CONTAINER_NAME /bin/bash
```

Once in the container you will have access to the `ensembl_databases.py` and `load_mysql.sh` commands and is the recommended way to use the `load_mysql.sh` command as working with MySQL 4 databases can be problematic if you lack the compatible binaries/libraries.

## Stopping the container

```sh
docker stop $CONTAINER_NAME
```

## Restarting the container

```sh
docker restart $CONTAINER_NAME
```

# Experimental Singularity support

**The following comand will start up a MySQL server on your local machine and expose a port on 3306**.

```sh
export LOCAL_DB_DIR=/volume1/docker/mysql
export LOCAL_FLATFILES_DIR=/volume1/docker/flatfiles
export MYSQL_ROOT_PASSWORD=mysql4mirror
export TAG=latest
singularity exec --bind $LOCAL_DB_DIR:/db --bind $LOCAL_FLATFILES_DIR:/flatfiles docker://ensemblorg/mysql4mirror:${TAG} /additional/start.sh mysqld_safe
```

The first time you run `/additional/start.sh` will setup the correct user permissions and will then initate `mysqld_safe`. This will start the MySQL server. Subsequent runs will test `/db` for pre-existing files, which if found means setup will be skipped and only `mysqld_safe` will be run.

## Starting a container shell session with Singularity

```sh
singularity shell --bind $LOCAL_DB_DIR:/db --bind $LOCAL_FLATFILES_DIR:/flatfiles docker://ensemblorg/mysql4mirror:${TAG}
```

This will start a new container with access to the MySQL data directory and flatfiles directory under `/db` and `/flatfiles` respectively.

# Populating the running instance with Ensembl databases

## Getting databases from Ensembl

### Using `ensembl_databases.py`

This container ships with a Python binary which can list, download and verify databases from releases 23 to 47 (those which should be hosted in a MySQL v4 instance). The library only uses core modules and is compatible with Python v3.2+. You can run it from within the container or from this repository. The binary can

- List the available databases
- Display information about the database
- Download the flat files
- Verify they are good

```sh
$ ./ensembl_databases.py --list '*help*28*' 
ensembl_help_28_1
$ ./ensembl_databases.py --download ensembl_help_28_1
Logging into ftp.ensembl.org
Listing database files for ensembl_help_28_1
Downloading ./ensembl_help_28_1/CHECKSUMS.gz
Downloading ./ensembl_help_28_1/article.txt.table.gz
Downloading ./ensembl_help_28_1/category.txt.table.gz
Downloading ./ensembl_help_28_1/ensembl_help_28.sql.gz
$ ./ensembl_databases.py --validate ensembl_help_28_1
All files are correct
```

The above command downloads the `ensembl_help_28_1` database to the local directory. You can use the `--basedir` flag to use a different location e.g. `/flatfiles` on the Docker container.

The binary takes as its final an unbounded list of database names or UNIX style glob strings (using `*` and `?` as wildcard characters). The following finds all compara and help databases available for release 28. 

**Be sure to quote your wildcard strings as command line shells will interpret this before `ensembl_databases.py` does.**

```
$ ./ensembl_databases.py --list '*compara*28*' '*help*28*'
ensembl_compara_28_1
ensembl_help_28_1
```

### Manually downloading files

If you want to manually download the database dumps, then you can use our [FTP site using FTP or HTTP](https://www.ensembl.org/info/data/ftp/index.html), [rsync](https://www.ensembl.org/info/data/ftp/rsync.html) or even Globus through the “Shared EMBL-EBI public endpoint”. 

## Loading into MySQL 

_The following commands assume you will be loading the `ensembl_help_28_1` database from flatfile dumps into a database._

### Using `load_mysql.sh`

This container and repo ship with a bash script called `load_mysql.sh`. The script must be executed from within a working directory containing a database dump. The command will change its commands based on if it finds the `ENSEMBL_CONTAINER` environment variable. You can change the port used too by supplying a `MYSQL_PORT` environment variable.

**`load_mysql.sh` executes all commands in MySQL as the root user. The script repsonds to the `MYSQL_ROOT_PASSWORD` variable and will use this if ever defined.**

We recommend running `load_mysql.sh` from within a container (see instructions above about how to get a shell session into the executing container or a new container).

```sh
$ cd ensembl_help_28_1
$ load_mysql.sh
!!!!!! Working with database ensembl_help_28

Working with table article
    Gunzipping article data from file article.txt.table.gz into article.txt ... Done
ensembl_help_28.article: Records: 66  Deleted: 0  Skipped: 0  Warnings: 0
    Finished and removed temporary file article.txt
Working with table category
    Gunzipping category data from file category.txt.table.gz into category.txt ... Done
ensembl_help_28.category: Records: 1  Deleted: 0  Skipped: 0  Warnings: 0
    Finished and removed temporary file category.txt

!!!!!! Database has been loaded
```

### Manual loading

To manually load a database you must

- Create the database (N.B. the directory name does not always match the intended database name but the SQL file will)
- Load the Gzipped SQL file (N.B. a `compatible_40` version is sometimes made available but not necessary to use)
- Load each table of data from the gzip'd flat files

The following shows the same procedure as used by the `load_mysql.sh` script for `ensembl_help_28`.

```sh
$ cd ensembl_help_28_1
$ dbname=ensembl_help_28
$ mysql -e "create database ${dbname}"
$ gzip -dc ensembl_help_28.sql.gz | mysql $dbname
$ gzip -dc article.txt.table.gz > article.txt
$ mysqlimport $dbname article.txt
$ rm article.txt
$ gzip -dc category.txt.table.gz > category.txt
$ mysqlimport $dbname category.txt
$ rm category.txt
```

The above commands can be also used from your local machine if you have access to the above binaries (`gzip` and `mysqlimport`) but the `mysqlimport` command needs the addition of `--local` to force it to copy said file to the database container automatically. You are also free to customise/use any user you use with sufficient database privilages.

# Building the container
```sh
docker build -t ensemblorg/mysql4mirror .
```

# Container details

## exposed Ports
```sh
# mysql  
EXPOSE 3306
```

## Volumes
```sh
VOLUME /db # mysql datadir
VOLUME /flatfiles # Location of Ensembl flat file database dumps
```

### Environment variables used
```sh
MYSQL_ROOT_PASSWORD	mysql4
TZ	Europe/London
ENSEMBL_DBLOOKUP /etc/dblookup.json
ENSEMBL_CONTAINER true
```

Root password will be bound to the wildcard % host to allow login from any network host.

# Testing status and support

These scripts have been tested with `ensembl_help_28` and `homo_sapiens_core_40_36b`. Should you encounter a problem with running these scripts then [contact Ensembl helpdesk or our developers mailing list](https://www.ensembl.org/info/about/contact/index.html).
