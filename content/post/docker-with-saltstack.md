+++
author = "Valentin Ouvrard"
categories = ["docker", "saltstack", "devops"]
date = 2016-08-24T10:09:34Z
description = ""
draft = false
slug = "docker-with-saltstack"
tags = ["docker", "saltstack", "devops"]
title = "Docker with Saltstack"

+++


![](/content/images/2016/08/docker-salt-banner.png)

Docker is a fantastic but sometimes container management can be complicated. To simplify and automate Docker application deployments we can use Saltstack, a strong configuration management written in Python and using ZeroMQ for dial with servers (called minions).

In this post, I'll show you how-to use Saltstack on a virtual cloud server based on Debian or Ubuntu. Salt will be used in a standalone mode, without master server. 

## Install Saltstack on your server
We're going to install **salt-minion** who'll manage our deployment.When your Salt code will be written you can re-use it to deploy again and again your application.

We'll use **Salt-Bootstrap** to automatically install Saltstack on our server, for this, run these commands :
```language-bash
wget -O install_salt.sh https://bootstrap.saltstack.com
sudo sh install_salt.sh
```

Because pipe over the internet is a bad idea. 


Salt should be installed few minutes later. We need to inform him that it will use the standalone mode (and not the master-client mode). For this, edit the **/etc/salt/minion** file :
```language-bash
file_client: local
```

Now, we can restart Salt-minion :
```language-bash
service salt-minion restart
```

If Salt is correctly installed, we can try to ping itself :
```language-bash
salt-call test.ping
```
We use **Salt-call** in a standalone mode.
## Write our Docker configuration

When Salt is installed on your server, we'll be able to deploy Docker and our Application configuration with some YAML files. 

We start with **/srv/salt/docker.sls** :
```language-yaml
import-docker-key:
  cmd.run:
    - name: apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    - creates: /etc/apt/sources.list.d/docker.list
/etc/apt/sources.list.d/docker.list:
  file.managed:
    - source: salt://docker.list

docker:
  pkg.installed:
    - name: docker-engine
service.running:
  - name: docker
  - require:
    - pkg: docker-engine
```

This **State** (YAML file) install Docker and ensure the service is correctly running. We need to create the proper **docker.list** file with our PPA information (example for Debian 8) :

```language-bash
echo "deb https://apt.dockerproject.org/repo debian-jessie main" > /srv/salt/docker.list
```

Now, we can create our application state in **/srv/salt/app.sls** :

```language-yaml
repo/my_app:
  dockerng.image_present:
    - force: true
    - name: repo/my_app:latest

my_app:
  dockerng.running:
    - name: my_adpp
    - image: repo/my_app:latest
    - port_bindings: 80:80
```

This state first pull our image in the latest version then launch our container called **my_app** and with TCP port 80 exposed. 

This example is quite simple but we can easily add some parameters to restrain resources or build our own image directly from Salt.
For this, I'll invite you to take a look on Saltstack [documentation.](https://docs.saltstack.com/en/latest/ref/states/all/salt.states.dockerng.html)

At this point, our application configuration is finished, we need to test it. But however, we add to create the **/srv/salt/top.sls** file for inform Salt what States it must use :

```language-yaml
base:  
  '*':
    - docker
    - app
```

## Deploy our application
Our server is now ready to receive our application through Saltstack. 
We're going to use the Highstate module who apply all the states present in the **top.sls** file. 

```language-bash
salt-call state.highstate
```

You can use `test=True` if you want to stimulate the Highstate. 

The first launch can take few minutes because it install Docker and pull your image. If all the steps correctly pass, you should have a confirmation by Saltstack :

![](/content/images/2016/08/salt-docker-launch.png)

We can verify our container running using Docker CLI (I'll use **tutum/lamp** in my case) :

![](/content/images/2016/08/docker-ps-tutum.png)
![](/content/images/2016/08/salt-tutum-docker.png)
There you go ! Your web application is perfectly deployed using Docker managed by Saltstack. No more container started manually anymore. 
You can use a git repo to host all your Salt's states for easily deploy codes on your servers.

You can also run the highstate periodically to ensure Docker stay correctly installed and running and for be sure that your application stay up. 

```language-bash
00 00 * * * salt-call state.highstate
```

Docker is great but Docker managed by Saltstack, is better. 

Last example, a state to run a persistent Wordpress application : 

```language-yaml
wordpress_app:
  dockerng.running:
    - name: wordpress_app
    - image: repo/wordpress:latest
    - port_bindings: 80:80
    - environment:
      - WORDPRESS_DB_HOST: db:3306
      - WORDPRESS_DB_PASSWORD: wordpress
    - links: wordpress_db:mysql

wordpress_db:
  dockerng.running:
    - name: wordpress_db
    - image: repo/mariadb:latest
    - ports: 3306/tcp    
    - binds: ./mysql:/var/lib/mysql:rw
    - environment:
      - MYSQL_ROOT_PASSWORD: wordpress
      - MYSQL_DATABASE: wordpress
      - MYSQL_USER: wordpress
      - MYSQL_PASSWORD: wordpress
```

