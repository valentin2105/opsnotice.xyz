+++
author = "Valentin Ouvrard"
categories = ["docker", "cluster", "devops", "rancher"]
date = 2016-08-18T22:09:47Z
description = ""
draft = false
slug = "overview-rancher-ui"
tags = ["docker", "cluster", "devops", "rancher"]
title = "Overview of Rancher UI"

+++


![](/content/images/2016/08/bannerrancher.png)

Today, I'll introduce you to Rancher UI, a Docker cluster management system, allowing deploy containers across multiple Docker hosts. 
You can manage your own Docker servers, deploy VMs on the cloud or add your Swarm, Kubernetes or Mesos existent clusters.   

> Say hello to Rancher, the container management platform that makes everything easy.

The goal of Rancher UI is to manage some Docker hosts (virtual or physical) from a Web interface which ensures container orchestration. 

In this example, I'll use 3 VMs on Debian Jessie :

- Manager (The Rancher UI server)
- Node01
- Node02

The Rancher UI server can be launched easily with a `docker run` :
```language-bash
docker run -d --restart=always -p 8080:8080 rancher/server
```
You can now reach the TCP port 8080 of your Manager server and admire the nice Rancher web interface :

![](/content/images/2016/08/rancher_ui.png)

We'll add our two nodes in our Rancher cluster. For this, let's go to **Infrastructure / Hosts** :

![](/content/images/2016/08/rancher_addhost.png)

You just have to click on **Add Host** who'll generate a Docker command to launch on our nodes servers. 

![](/content/images/2016/08/addhostrancher-.png)

(Copy-paste the command and run it on each node)

With Rancher, you can add some private Docker server (in our case) or directly spawn VMs from cloud-providers like AWS or Digital Ocean. 

Since our two nodes are added, we can take a look at our cluster :

![](/content/images/2016/08/rancherhosts.png)

At this point, you’re the happy owner of a Rancher cluster !

This cluster's goal is to deploy application isn't it ? 
So, we'll deploy our first application, **Owncloud** for example. For this, we go to **Catalog** section and we choose our app :

![](/content/images/2016/08/owncloud_rancher-e1461207835915.png)
![](/content/images/2016/08/owncloudup_rancher.png)

You can add this application, wait few minutes (for pulling all images) and reach your TCP port 80 on node01 to enjoy your new Private Cloud :

![](/content/images/2016/08/owncloud_logiin-e1461208614910.png)

Rancher offers tens of pre-packaged applications available in the **Catalog** section :

![](/content/images/2016/08/Catalog-with-Hadoop-e1461229809127.png)

Another example, for monitoring our Rancher cluster, we can easily add **Prometheus** stack to monitor all our Docker hosts in a **Grafana** interface with ready to use dashboards :

![](/content/images/2016/08/grafana_rancher.png)

For sure, you can deploy a simple container like you do it on a classic Docker host. For this, let's go in the **Container** section :

![](/content/images/2016/08/container_rancher.png)

Voilà, we have done a small overview of Rancher UI potential. I would probably write another post for go deeper in Rancher capacities. Know you can easily create your own Application stacks (like Docker-compose), manage some pool storage, manage your own image registry and plenty of other cool stuff. 

Last thing, it's recommended accessing at your Rancher web interface with some TLS encryption. For this you can follow the [documentation](http://docs.rancher.com/rancher/v1.2/en/installing-rancher/installing-server/basic-ssl-config/).

