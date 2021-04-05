+++
author = "Valentin Ouvrard"
categories = ["docker", "docker-compose", "go", "deployment"]
date = 2017-07-10T03:37:00Z
description = ""
draft = false
slug = "deployer-multi-stage-dockercompose"
tags = ["docker", "docker-compose", "go", "deployment"]
title = "Multi-stage deployment w/ deployer"

+++


---
Few weeks ago, I needed something to manage easily multi-stages (dev, integration, prod) environments for a Symfony app w/ Redis and Websockets on multi docker-compose files. 
So every environment got these own particularities. 

To do that easily next times, I built a small go tool called **deployer**. 

![](/content/images/2017/07/go-deployer-small.png)

Its use is quite simple :

You create a simple `config.json` file with all your environment (dev, prod for Wordpress in this example) :
```
{
   “config”:
 {
     “WpImage”: “wordpress:latest”,
     “DBImage”: “mysql:latest”,
     “NginxImage”: “nginx:latest”
 },
   “dev”:
 {
     “Tag”: “dev”,
     “Vhost”: “dev.nautile.plus”,
     "DBPassword": "AnyGoodPassword",
     "DBName": "mydevsite",
     "ExpositionPort": "8001:80"
 },
   “prod”:
 {
     “Tag”: “integration”,
     “Vhost”: “integration.nautile.plus”,
     "DBPassword": "AnyBetterPassword",
     "DBName": "myprodsite",
     "IPv6Network": "ff00:c210::/64",
     "IPv6": "ff00:c210::121"
 }
}
```
I put this `config.json` in the root on my Git repository then create docker-compose files in a **compose/** folder for each environment needed and formatthem using Go templating with variables from the `config.json`. 

For example, **compose/dev.tmpl.yml** :
```
version: '2'
services:
  wordpress:
    image: {{.config_WpImage}}
    ports:
      - {{.dev_ExpositionPort}}
    volumes:
      - /var/www/html 
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: {{.dev_DBName}}
      WORDPRESS_DB_USER: root
      WORDPRESS_DB_PASSWORD: {{.dev_DBPassword}}
    depends_on:
      - db
    links:
      - db

  db:
    image: {{.config_DBImage}}
    volumes:
      - /var/lib/mysql
    environment:
      MYSQL_DATABASE: {{.dev_DBName}}
      MYSQL_ROOT_PASSWORD: {{.dev_DBPassword}}
```
As you see, the variable from JSON Dev:DBName will be parsed in the compose with the go value {{.dev_DBName}} ( _ is the separator).

Now, we can download latest deployer binary and deploy it on our Laptop / VM / Bare-metal server. The only dependencies are Docker (configured locally or to talk to distant docker host) and Docker-compose.
```
wget https://github.com/valentin2105/deployer/releases/download/v0.1.5/deployer -O /usr/local/bin/deployer

chmod +x /usr/local/bin/deployer
```
Then launch our wanted environment :
```
deployer add dev
deployer add prod
```
![](https://i.imgur.com/ngkdqr0.gif)

Code base is present [here](https://github.com/valentin2105/deployer). 

All templates are generated to a **.generated/** folder, then `docker-compose pull` is run from it and finally `docker-compose up -d`. 
So **deployer** is used also for update environment (if new images are created).   

If you use Hipchat, simply add `hipchatRoom` and `hipchatToken` in the config section of the `config.json` to get notified of every deployment. 

If you add a key `Hook` and `HookWaitTime` in the environment section, **deployer** will wait the time you provide before executing the Hook script (and this, for every stage you defined). 

This tool allows you to tweak more in depth between your different stages, for example :

You can have a lot of environments in **compose/** folder :
```
compose/
        dev.tmpl.yml
        localhost.tmpl.yml
        integration.tmpl.yml
        pre-prod.tmpl.yml
        prod.tmpl.yml
```
Then you can write all your configurations in the `config.json` file, for example : 

- send logs to ELK for prod template 
- different IP(v4/v6) for each stage
- volume mounted for the development process
- different image tags between environments
- different environment variables (Passwords, host ...)

**deployer** can also become a step in your CI process to deploy your containers on the wanted Docker host. 

Issues / Pull requests are welcome !

