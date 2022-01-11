FROM ubuntu:12.04
LABEL maintainer="helpdesk@ensembl.org"

#env
ENV DEBIAN_FRONTEND noninteractive
ENV HOSTNAME mysql4
ENV TZ Europe/London
ENV TERM linux
ENV PATH /usr/local/mysql/bin:$PATH
ENV ENSEMBL_CONTAINER='true'

RUN sed -i -e 's/archive.ubuntu.com\|security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
RUN apt-get update 
RUN apt-get install -q -y build-essential libncurses5-dev bison less vim python3

#locale
RUN locale-gen en_GB.UTF-8 && locale-gen en_US.UTF-8 && dpkg-reconfigure locales 
#Time
RUN echo "$TZ" > /etc/timezone && dpkg-reconfigure -f noninteractive tzdata

#add mysql user and sources
RUN groupadd -r mysql && useradd -r -g mysql mysql

#compile mysql4 from source
COPY compile_mysql4.sh mysql-4.1.25.tar.gz /root/
RUN chmod +x /root/compile_mysql4.sh
RUN /root/compile_mysql4.sh

#add entrypoint but under /additional
RUN mkdir /additional
RUN chmod ugo+rx /additional
COPY start.sh stop_mysql.sh /additional/
RUN chmod ugo+x /additional/*.sh

#interfaces
EXPOSE 3306
VOLUME /db
VOLUME /flatfiles

# Add Ensembl scripts
COPY ensembl_databases.py /bin/.
RUN chmod ugo+x /bin/ensembl_databases.py
COPY load_mysql.sh /bin/.
RUN chmod ugo+x /bin/load_mysql.sh
COPY dblookup.json /etc/.
ENV ENSEMBL_DBLOOKUP /etc/dblookup.json

#define entrypoint
ENTRYPOINT ["/additional/start.sh"]
CMD ["mysqld_safe"]
