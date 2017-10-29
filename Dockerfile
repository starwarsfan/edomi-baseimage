FROM centos:6.8
MAINTAINER Yves Schumann <y.schumann@yetnet.ch>

RUN yum update -y \
 && yum upgrade -y \
 && yum -y install \
	nano \
	wget \
	unzip \
	php-devel \
	mysql \
	mysql-server \
	vsftpd \
	httpd \
	tar \
	php-gd \
	php-mysql \
	php-pear \
	php-soap \
	ntp \
	openssh-server \
	mod_ssl
