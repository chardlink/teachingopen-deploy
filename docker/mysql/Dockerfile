FROM mysql:5.7

COPY docker/mysql/conf.d/local.cnf /etc/mysql/conf.d/local.cnf
COPY docker/mysql/initdb/01-import-base.sh /docker-entrypoint-initdb.d/01-import-base.sh
COPY assets/teachingopen2.8.sql /seed/teachingopen2.8.sql

RUN chmod +x /docker-entrypoint-initdb.d/01-import-base.sh
