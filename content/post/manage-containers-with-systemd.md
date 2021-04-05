+++
author = "Valentin Ouvrard"
categories = ["linux", "docker", "system"]
date = 2016-07-25T19:09:58Z
description = ""
draft = false
slug = "manage-containers-with-systemd"
tags = ["linux", "docker", "system"]
title = "Manage containers with Systemd"

+++


![](/content/images/2016/07/banner-systemd-1.png)

Use Docker containers on the fly is quite easy but sometimes container management by shell becomes difficult. For easily launch and restart your container, we can use a Systemd unit. 

## Create Unit file
In this example, I use a REDIS image that run with docker.
We need to create the file **/etc/systemd/system/redis.service** :
```langage-bash
[Unit]
Description=Redis Service  
After=docker.service  
Requires=docker.service

[Service]
ExecStartPre=-/usr/bin/docker kill redis  
ExecStartPre=-/usr/bin/docker rm redis  
ExecStartPre=-/usr/bin/docker pull redis:latest
ExecStart=/usr/bin/docker run  -d --name redis --restart always redis:latest  
ExecStop=/usr/bin/docker stop redis

[Install]
WantedBy=multi-user.target  
```
This file will wait until the docker service is running then delete old redis container, pull last redis image and finally launch our container.

Let's enable redis.service and launch it :
```language-bash
systemctl enable redis
systemctl daemon-reload
systemctl start redis
```
## Verify our container
After the `systemctl start` you can check your running container with `docker ps` :

![](/content/images/2016/07/dockerps-redis.png)

## Using with docker-compose
You can use a Systemd unit file for Docker-compose too like this :
```langague-bash
ExecStartPre=-/usr/local/bin/docker-compose -f compose-file.yml down
ExecStart=/usr/local/bin/docker-compose -f compose-file.yml up -d
ExecStop=/usr/local/bin/docker-compose -f compose-file.yml stop
```
With this, you can start your stack of containers using Systemd.

