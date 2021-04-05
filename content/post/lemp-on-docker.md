+++
author = "Valentin Ouvrard"
categories = ["docker", "lemp", "linux", "docker-compose", "tls"]
date = 2016-07-24T03:28:15Z
description = ""
draft = false
slug = "lemp-on-docker"
tags = ["docker", "lemp", "linux", "docker-compose", "tls"]
title = "LEMP on Docker"

+++


![](/content/images/2016/07/banner_lemp1-1.png)

In this first post, I'll show you how to deploy a LEMP Server (Linux, Nginx, MariaDB, PHP) with Docker on Debian Jessie.

## Why ?

The advantage of use Docker in this case is that you can deploy it first on your laptop for your development process and finally deploy it easily on a Docker-based VM directly in the Cloud. 

## Install Docker
The first step is the installation of Docker-Engine and Docker-Compose. I use Debian 8 in this example :
```language-bash
apt-get install -y apt-transport-https ca-certificates python-pip
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
echo "deb https://apt.dockerproject.org/repo debian-jessie main" > /etc/apt/sources.list.d/docker.list
apt-get update ; apt-get -y install docker-engine
pip install docker-compose
```
## Compose your Stack
We'll use Docker-Compose to describe our stack of containers. I create a **docker-compose.yml** file like this (in the **/srv** directory) :

```language-yaml
web_db:
   image: mariadb:latest
   restart: always
   volumes:
    - ./mysql:/var/lib/mysql
   environment:
    MYSQL_ROOT_PASSWORD: @Str0NgP@Ssw0rd

web_front:
  image: nginx
  restart: always
  ports:
    - 80:80
    - 443:443
  log_driver: syslog
  links:
    - web_fpm
  volumes:
    - ./www:/var/www/html:rw
    - ./nginx.conf:/etc/nginx/nginx.conf:ro
    - ./logs/nginx:/var/log/nginx:rw
    - /etc/letsencrypt:/etc/letsencrypt:rw
    - ./dhparam.pem:/etc/nginx/certs/dhparam.pem:ro

web_fpm:
  build: .
  restart: always
  links:
    - web_db:mysql
  volumes:
    - ./www:/var/www/html
```
The first block launch MariaDB with a volume for export data, the second block launch Nginx on ports 80 and 443 with some volumes for the web folder, logs and certs. The last block launch PHP-FPM based on a DockerFile (build directive) linked with the database and sharing the same web folder.
## Build PHP image
We have to build our own PHP-FPM image for insert all the module that we want. So I create this **DockerFile** :

```language-docker
FROM php:7.0.8-fpm

RUN apt-get update && apt-get install -y libpng12-dev libjpeg-dev && rm -rf /var/lib/apt/lists/* \
	&& docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
	&& docker-php-ext-install gd mysqli opcache

RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

VOLUME /var/www/html

COPY docker-entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
```
You can easily add some PHP modules after those I add by default (`gd, mysqli, opcache`). 
Last step for PHP, let's create the **docker-entrypoint.sh** file :
```language-bash
#!/bin/bash
set -e
exec "$@"
```
## Nginx & TLS
After this, we can setup our Nginx configuration for use TLS with the free Certificate Authority, Let's Encrypt. 
We must generate a dhparam file using openssl :
```langage-bash
openssl dhparam -out dhparam.pem 4096
```
Then, we can create our certificates using Docker, of course :
```language-docker
docker run -it --rm -p 443:443 -p 80:80 --name letsencrypt \
-v "/etc/letsencrypt:/etc/letsencrypt" \
-v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
quay.io/letsencrypt/letsencrypt:latest auth
```
This container will ask you if you want to use a temporary server, choose it and give it your domain name and your e-mail. (Of course, don't forget to correctly redirect your DNS on this server). 

Now, we can create the **nginx.conf** file :

```language-nginx
worker_processes  1;
events {
    worker_connections  1024;
}
 
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65; 
    gzip on;
    gzip_disable "msie6";  
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
    
    server {
      listen         80;
      server_name    example.com;
      return         301 https://$server_name$request_uri;
    }

    server {
      listen 443 ssl http2;
      ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem; 
      ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
      ssl_session_timeout 1d;
      ssl_session_cache shared:SSL:50m;
      ssl_session_tickets off;
      ssl_protocols TLSv1.1 TLSv1.2;
      ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK';
      ssl_prefer_server_ciphers on;
      ssl_dhparam /etc/nginx/certs/dhparam.pem; 
      add_header Strict-Transport-Security max-age=15768000;
      ssl_stapling on;
      ssl_stapling_verify on;
      ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem; 
      resolver 8.8.8.8 8.8.4.4 valid=86400;
      root /var/www/html;
      index index.php;
      location / {
        try_files $uri $uri/ /index.php?$args;
      }        
      location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        if (!-f $document_root$fastcgi_script_name) {
        	return 404;
        }
          root           /var/www/html;
          fastcgi_pass   web_fpm:9000;
          fastcgi_index  index.php;
          fastcgi_param SCRIPT_FILENAME /var/www/html$fastcgi_script_name;
          include        fastcgi_params;
      }    
    }
}
```
You have to replace all occurrences of **example.com** with your domain name. Do it quickly with Vim :
`:%s/example.com/new-domain.com/g`

We have finished our configurations, we can build our containers and launch them now : 
```langage-docker
docker-compose build; docker-compose up -d
```
## Check it up
Let's make a check about PHP version, create a **info.php** into **/srv/www/** :
```language-php
<?php
phpinfo();
?>
```
![](/content/images/2016/07/php-version.png)
  
For check our TLS connexion, I use [SSLLabs](https://www.ssllabs.com/ssltest/) : 
  
![](/content/images/2016/07/ssllab-result.png)

For automatically renew your certificates, you can create a cron with this Docker command (every months for example):

```language-docker
docker run -it --rm --name letsencrypt \
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/srv/www:/srv/www" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  quay.io/letsencrypt/letsencrypt \
  certonly \
  --webroot \
  --webroot-path /srv/www \
  --agree-tos \
  --renew-by-default \
  -d example.com \
  -m contact@example.com
```

