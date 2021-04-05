+++
author = "Valentin Ouvrard"
categories = ["docker", "docker-compose", "git"]
date = 2016-08-07T21:26:00Z
description = ""
draft = false
slug = "gogs-git-docker"
tags = ["docker", "docker-compose", "git"]
title = "Deploy Gogs, a Git server"

+++


## ![](/content/images/2016/08/gogs-e1461040668891.png)

I'll show you how-to deploy Gogs, a Git server with a webUI, wrote in Go. We'll use Docker-compose for launch Gogs and Nginx secured with HTTPS using Let's Encrypt.
> Gogs (Go Git Service) is a painless self-hosted Git service.

For starting, we need to create some folders to receive our Gogs stack :
```language-bash
mkdir /srv/Gogs
mkdir -p /srv/Gogs/etc/nginx
mkdir -p /srv/Gogs/etc/certs
```
For sure, we need Docker in our server, I use Debian Jessie in my case :
```language-bash
apt-get install -y apt-transport-https ca-certificates python-pip
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
echo "deb https://apt.dockerproject.org/repo debian-jessie main" > /etc/apt/sources.list.d/docker.list
apt-get update ; apt-get -y install docker-engine
pip install docker-compose
```
Next, we'll generate our TLS certificates using a Let's Encrypt container who launches a temporary web-server.
For this, reply to the answers asked by the container (e-mail and domain) :
```language-docker
docker run -it --rm -p 443:443 -p 80:80 --name letsencrypt \
            -v "/etc/letsencrypt:/etc/letsencrypt" \
            -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
            quay.io/letsencrypt/letsencrypt:latest auth
``` 
Now, we have our certs in **/etc/letsencrypt**, we can create the main Nginx configuration file named **nginx.conf**:
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
    gzip_buffers 16 32k;
    gzip_min_length  1100;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
   
    server {
      listen         80;
      server_name    git.domain.com; #Remplacer par votre nom de serveur
      return         301 https://$server_name$request_uri;
    }
    server {
      listen 443 ssl http2;
      ssl_certificate /etc/letsencrypt/live/git.domain.com/fullchain.pem; #Remplacer par votre chemin
      ssl_certificate_key /etc/letsencrypt/live/git.domain.com/privkey.pem; #Remplacer par votre chemin
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
      ssl_trusted_certificate /etc/letsencrypt/live/git.domain.com/chain.pem; 
      resolver 8.8.8.8 8.8.4.4 valid=86400;
    location / {
        proxy_read_timeout      300;
        proxy_connect_timeout   300;
        proxy_redirect          off;
        proxy_set_header        X-Forwarded-Proto $scheme;
        proxy_set_header        Host              $http_host;
        proxy_set_header        X-Real-IP         $remote_addr;
        proxy_set_header        X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header        X-Frame-Options   SAMEORIGIN;
        proxy_set_header X-Forwarded-Ssl on;
        proxy_pass              http://gogs_engine:3000;
        }
	}
} 
```
Don't forget to replace all occurrences of git.domain.com with your domain name, do it quickly with vim :
`%s/git.domain.com/your.domain.com/g`

Now, we can create **docker-compose.yml** to describe our stack :
```language-yaml
gogs_web:
  image: nginx
  restart: always
  ports:
    - 443:443
    - 80:80
  volumes:
     - .nginx.conf:/etc/nginx/nginx.conf:ro
     - ./var/log/nginx:/var/log/nginx
     - /etc/letsencrypt:/etc/letsencrypt
     - ./certs/dhparam.pem:/etc/nginx/certs/dhparam.pem
  links:
    - gogs_engine
gogs_engine:
  image: gogs/gogs:latest
  restart: always
  ports:
    - '2222:22'
  expose: 
    - '3000'
  volumes:
    - ./var/gogs:/data
```
For some details, this file launch at first a Nginx container who binds ports 80 and 443 with some volumes for config, certs, logs and it's linked to a second container of Gogs who listens on port 2222 for SSH connexions. Nginx and Gogs are speaking on the port 3000 linked in this file. Gogs also have a volume for stock data of our Git server.

Before launch our stack, we need to create a DHParam file using OpenSSL :
```language-bash
cd /srv/Gogs/etc/certs
openssl dhparam -out dhparam.pem 2048
```

Finally, we can launch our Containers stack :
```language-bash
docker-compose up -d 
```
Few seconds later, you can reach your server to configure your fresh Gogs server. 
You need to set up a database, you can easily use SQLite but if you want to use MySQL, you can add some lines on your docker-compose.yml file to add a MariaDB instance and link it to your Gogs container. 

![](/content/images/2016/08/gogs-config.png)

Your Git server is ready to receive your dev team !


![](/content/images/2016/08/gogs_interface-e1461042820636.png)

