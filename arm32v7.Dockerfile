FROM starwarsfan/edomi-baseimage-builder:arm32v7-latest as builder
MAINTAINER Yves Schumann <y.schumann@yetnet.ch>

# Dependencies to build stuff
RUN yum -y install mosquitto mosquitto-devel mysql-devel php-devel which

# For 19001051 (MQTT Publish Server)
RUN cd /tmp \
 && git clone https://github.com/mgdm/Mosquitto-PHP \
 && cd Mosquitto-PHP \
 && phpize \
 && ./configure \
 && make \
 && make install DESTDIR=/tmp/Mosquitto-PHP

RUN cd /tmp \
 && mkdir -p /tmp/Mosquitto-PHP/usr/lib64/mysql/plugin \
 && git clone https://github.com/jonofe/lib_mysqludf_sys \
 && cd lib_mysqludf_sys/ \
 && gcc -DMYSQL_DYNAMIC_PLUGIN -fPIC -Wall -I/usr/include/mysql -I. -shared lib_mysqludf_sys.c -o /tmp/Mosquitto-PHP/usr/lib64/mysql/plugin/lib_mysqludf_sys.so

RUN cd /tmp \
 && git clone https://github.com/mysqludf/lib_mysqludf_log \
 && cd lib_mysqludf_log \
 && autoreconf -i \
 && ./configure \
 && make \
 && make install DESTDIR=/tmp/Mosquitto-PHP

FROM arm32v7/centos:7
MAINTAINER Yves Schumann <y.schumann@yetnet.ch>

COPY qemu-arm-static /usr/bin/

# Workaround for https://github.com/multiarch/centos/issues/1
RUN echo "armhfp" > /etc/yum/vars/basearch \
 && echo "armv7hl" > /etc/yum/vars/arch \
 && echo "armv7hl-redhat-linux-gpu" > /etc/rpm/platform

RUN yum update -y \
 && yum upgrade -y \
 && yum install -y \
        epel-release \
 && yum update -y \
 && yum install -y \
        ca-certificates \
        file \
        git \
        hostname \
        httpd \
        mariadb-server \
        mod_ssl \
        mosquitto \
        mosquitto-devel \
        nano \
        net-snmp-utils \
        net-tools \
        ntp \
        openssh-server \
        tar \
        unzip \
        vsftpd \
        wget \
        yum-utils \
 && yum clean all

COPY epel.repo /etc/yum.repos.d/
COPY php74-testing.repo /etc/yum.repos.d/
COPY remi.repo /etc/yum.repos.d/

RUN yum install -y \
        php \
        php-curl \
        php-gd \
        php-mbstring \
        php-mysql \
        php-process \
        php-snmp \
        php-soap \
        php-ssh2 \
        php-xml \
        php-zip \
 && yum clean all \
 && rm -f /etc/vsftpd/ftpusers \
          /etc/vsftpd/user_list

# Alexa
RUN ln -s /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/cacert.pem \
 && sed -i \
        -e '/\[curl\]/ a curl.cainfo = /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' \
        -e '/\[openssl\] a openssl.cafile = /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' \
        /etc/php.ini

# Mosquitto-LBS
COPY --from=builder /tmp/Mosquitto-PHP/modules /usr/lib64/php/modules/
COPY --from=builder /tmp/Mosquitto-PHP/usr/lib64/mysql /usr/lib64/mysql/
COPY --from=builder /tmp/lib_mysqludf_log/installdb.sql /root/
RUN echo 'extension=mosquitto.so' > /etc/php.d/50-mosquitto.ini

# Get composer
RUN cd /tmp \
 && php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php -r "if (hash_file('sha384', 'composer-setup.php') === file_get_contents('https://composer.github.io/installer.sig')) { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
 && php composer-setup.php \
 && php -r "unlink('composer-setup.php');" \
 && mv composer.phar /usr/local/bin/composer \
 && mkdir -p /usr/local/edomi/main/include/php

# Telegram-LBS 19000303 / 19000304
RUN cd /usr/local/edomi/main/include/php \
 && git clone https://github.com/php-telegram-bot/core \
 && mv core php-telegram-bot \
 && cd php-telegram-bot \
 && composer install

# Mailer-LBS 19000587
RUN cd /usr/local/edomi/main/include/php/ \
 && mkdir PHPMailer \
 && cd PHPMailer \
 && composer require phpmailer/phpmailer

# MikroTik RouterOS API 19001059
RUN yum update -y \
        nss \
 && yum clean all \
 && cd /usr/local/edomi/main/include/php \
 && git clone https://github.com/jonofe/Net_RouterOS \
 && cd Net_RouterOS \
 && composer install

# Philips HUE Bridge 19000195
# As long as https://github.com/sqmk/Phue/pull/143 is not merged, fix phpunit via sed
RUN cd /usr/local/edomi/main/include/php \
 && git clone https://github.com/sqmk/Phue \
 && cd Phue \
 && sed -i "s/PHPUnit/phpunit/g" composer.json \
 && composer install

# Edomi
RUN systemctl enable ntpd \
 && systemctl enable vsftpd \
 && systemctl enable httpd \
 && systemctl enable mariadb

RUN sed -e "s/listen=.*$/listen=YES/g" \
        -e "s/listen_ipv6=.*$/listen_ipv6=NO/g" \
        -e "s/userlist_enable=.*/userlist_enable=NO/g" \
        -i /etc/vsftpd/vsftpd.conf \
 && mv /usr/bin/systemctl /usr/bin/systemctl_ \
 && wget https://raw.githubusercontent.com/starwarsfan/docker-systemctl-replacement/master/files/docker/systemctl.py -O /usr/bin/systemctl \
 && chmod 755 /usr/bin/systemctl

# Remove limitation to only one installed language
RUN sed -i "s/override_install_langs=.*$/override_install_langs=all/g" /etc/yum.conf \
 && yum update -y \
 && yum reinstall -y \
        glibc-common \
 && yum clean all
