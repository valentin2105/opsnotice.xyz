+++
author = "Valentin Ouvrard"
categories = ["nginx", "docker", "docker-compose", "tls"]
date = 2016-07-31T21:29:47Z
description = ""
draft = false
slug = "nginx-docker-tls-reverse-proxy"
tags = ["nginx", "docker", "docker-compose", "tls"]
title = "Nginx as a TLS reverse-proxy"

+++


![](/content/images/2016/07/lets_nginx_encrypt.png)

In this post, I'll show you how-to deploy a Nginx reverse-proxy with Let's Encrypt and SNI support for deserving multi-domains. I'll make this configuration on a Docker-based VM but you can, for sure, apply the same configuration on a hard Nginx installation. 

We're going to use Docker-compose to describe as we want our Nginx configuration, for this, I create **docker-compose.yml** :
```language-yaml
version: "2"
services:
 nginx-front:
   image: nginx:latest
   restart: always
   ports:
     - "443:443/tcp"
     - "80:80/tcp"
   volumes:
      - ./logs:/var/log/nginx
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./sites-enabled:/etc/nginx/sites-enabled
      - ./www/:/var/www
```
This file describes a Nginx container who'll bind on ports 80 and 443 with some volumes for configuration, certificates, logs and web folders.

Now, we can create our Nginx configuration.
The main Nginx file we need to create is the **nginx.conf** file :

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
    gzip_min_length  256;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript;
    include /etc/nginx/sites-enabled/*;
}
```
Now, we can create the directory **sites-enabled** and deploy your first website with the file **example.com** :
```language-nginx
    server {
      listen         80;
      server_name    example.com;
      return         301 https://$server_name$request_uri;
    }
    server {
      listen 443 ssl http2;
      server_name    example.com;
      ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem; 
      ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
      ssl_session_timeout 1d;
      ssl_session_cache shared:SSL:50m;
      ssl_session_tickets off;
      ssl_protocols TLSv1.1 TLSv1.2;
      ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK';
      ssl_prefer_server_ciphers on;
      ssl_dhparam /etc/letsencrypt/dhparam.pem;
      add_header Strict-Transport-Security max-age=15768000;
      ssl_stapling on;
      ssl_stapling_verify on;
      ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem; 
      root /var/www/example.com/html;
      index index.php;

      location / {
        proxy_pass http://your-website:8080;
        proxy_set_header Proxy "";
        proxy_set_header Accept-Encoding "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        add_header Front-End-Https on;
        add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
        client_max_body_size 1024M;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_connect_timeout 600s;
      }
    }
```
You can create a second website in the same folder replacing all occurrences of **example.com** by your second domain (**example.net** for example). Don't forget to modify the proxy_pass instruction which redirects requests to your insecure website (on a high tcp port for example). 

Before launch our Nginx container who's going to serve to secure websites on different domains, we need to create our certificates using the free Certificate Authority, Let's Encrypt. 
For this, we use Docker :

```language-bash
docker run -it --rm -p 443:443 -p 80:80 --name letsencrypt \ 
-v "/etc/letsencrypt:/etc/letsencrypt" \ 
-v "/var/lib/letsencrypt:/var/lib/letsencrypt" \ 
quay.io/letsencrypt/letsencrypt:latest certonly \ 
--standalone \ 
--agree-tos \ 
--renew-by-default \ 
-d example.com,example.net \ 
-m contact@example.com 
```
This command will launch a Let's Encrypt container who creates a temporary webserver to generate the certs for **example.com** and **example.net**.  It mounts **/etc/letsencrypt** as a volume than we can re-use this certificate with our Nginx container. 
For sure, DNS servers for your two domains have to point on the same server before generate the certs. 

Last steps before launch Nginx, we need to generate a Dhparam file using OpenSSL :
```language-bash
cd /etc/letsencrypt/ ; openssl dhparam -out dhparam.pem 4096
```
Now, we can launch Nginx using Docker-compose :
```language-bash
docker-compose up -d
```
You can finally test connexions to your websites which should work perfectly and secured using TLS (you can verify it on SSLLab). If there is a problem, you can check your logs in **logs/error.log**.

![](https://opsnotice.xyz/content/images/2016/07/ssllab-result.png)

For a bit of automation, we can create a crontab every weeks (Let's encrypt expire all 90 days) which renew our two certificates. For example :
```language-docker
docker run -it --rm --name letsencrypt \  
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/srv/www/example.com/html:/srv/www/example.com/html" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  quay.io/letsencrypt/letsencrypt \
  certonly \
  --webroot \
  --webroot-path /srv/www/example.com/html \
  --agree-tos \
  --renew-by-default \
  -d example.com, example.net \
  -m contact@example.com 
```
You can use the same command to generate certificates for a new domain before deploying a new sites-enabled file and reloading the Nginx config to finally activate your new website.

For cleanly reload your Nginx configuration, you can send a SIGHUP signal to your container :
```language-docker
docker kill -s HUP nginx_front_1
```

