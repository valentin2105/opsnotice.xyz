+++
author = "Valentin Ouvrard"
categories = ["docker", "supervision", "grafana", "influxdb"]
date = 2016-07-29T06:05:17Z
description = ""
draft = false
slug = "how-to-monitor-docker-hosts"
tags = ["docker", "supervision", "grafana", "influxdb"]
title = "How-to monitor Docker  ?"

+++


The use of containers needs a strong supervision with different metrics than traditional VMs. For monitor Docker hosts, I use a stack of [InfluxDB](https://influxdata.com/) a time-series database, [Grafana](http://grafana.org/) the data visualiser and finally [Telegraf](https://github.com/influxdata/telegraf) to ship our metrics from few hosts.

![](/content/images/2016/07/grafana-dashboard.png)

I'll show you how-to deploy InfluxDB and Grafana on a docker host and install Telegraf on a Debian-based distribution.
For sure, we can use Telegraf on Docker but personally, I prefer to install it directly on hosts to make it more permanent. 
If docker go wrong, our metrics are already shipped. 

For launch my supervision stack, I use Docker-compose, you can install it easily using Python-pip :
```language-bash
apt-get -y install python-pip
pip-install docker-compose
```
Now, we can create our **docker-compose.yml** file :

```language-yaml
 influxdb:
   image: tutum/influxdb
   restart: always
   expose:
     - "8090"
     - "8099"
   ports:
     - "127.0.0.1:8083:8083"
     - "8086:8086"
   volumes:
     - /srv/influxdb:/data
   environment:
     - ADMIN_USER: "telegraf"
     - INFLUXDB_INIT_PWD: "Astr0ngPassw0rd"
     - PRE_CREATE_DB: "telegraf"
 grafana:
   image: grafana/grafana:latest
   restart: always
   ports:
     - "3000:3000"
   volumes:
     - /srv/grafana:/var/lib/grafana
   environment:
     - GF_SECURITY_ADMIN_PASSWORD: "Astr0ngPassw0rd"
```
This file will create a InfluxDB container with the port 8086 exposed on the Internet (to listen for metrics) with a volume for store data and a Grafana container with a volume for the configuration and the port 3000 exposed for the WebUI. 

For security reason, we change InfluxDB admin user and password because we expose our database on Internet, same thing for the Grafana UI.

At this point, we are ready to receive metrics and visualise them. For ship some metrics, I use Telegraf, a small Go tools who ship all metrics we need and add some interesting plugins like Network or Docker.

Let's download the last **.deb** file and install it on each of our Docker Hosts :
```language-bash
wget https://dl.influxdata.com/telegraf/releases/telegraf_1.0.0-beta3_amd64.deb
dpkg -i telegraf_1.0.0-beta3_amd64.deb
```
Now, Telegraf is installed, we can now create our configuration file. 
Let's create a new **/etc/telegraf/telegraf.conf** file :
```language-yaml
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  debug = false
  quiet = false
  hostname = ""
  omit_hostname = false
[[outputs.influxdb]]
  urls = ["http://<InfluxDB-publicIP>:8086"] # required
  database = "telegraf" # required
  retention_policy = ""
  write_consistency = "any"
  timeout = "5s"
  username = "telegraf"
  password = "Astr0ngPassw0rd"
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  fielddrop = ["time_*"]
[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs"]
[[inputs.diskio]]
[[inputs.kernel]]
[[inputs.mem]]
[[inputs.processes]]
[[inputs.swap]]
[[inputs.docker]]
  endpoint = "unix:///var/run/docker.sock"
[[inputs.net]]
  interfaces = ["eth0"]
```
This file is quite simple, we take metrics about cpu, disk, io, kernel, mem, processes, swap, network and Docker (this last plugin is very interesting for us). 

Before launch Telegraf, we had to add telegraf user to the docker group :
```language-bash
usermod -aG docker telegraf
service telegraf restart
```

Now, our Telegraf agent is sending hundred metrics to our InfluxDB container. Let's visualise them ! 
Go on http://your-ip:3000 and connect to Grafana with these credentials (**admin:Astr0ngPassw0rd**) :

![](/content/images/2016/07/grafana-login.png)

Before all, we need to connect Grafana with our InfluxDB instance, for this, add a Data Source :

![](/content/images/2016/07/add-datasource-grafana.png)

Now, we can create our first Dashboard, go to Dashboard > New :

![](/content/images/2016/07/create-dash-grafana.png)

After, we can add a graph :

![](/content/images/2016/07/create-graph-grafana.png)

Let's select some metrics (CPU Usage for example) :

![](/content/images/2016/07/first-graph-grafana.png)

Yeah ! we got our first graph. You can now create tons of graphs for CPU, Memory, Disks usage ... 

If you want to create a Network graph, you'll see a constant rise of your metrics. It's normal. To have a bytes/s graph you have to write a request like this :

```language-bash
SELECT derivative("bytes_sent", 1s) FROM "net" WHERE "host" = 'docker'
```

You can print a single value in your Dashboard, for example the number of containers running on our host. This is possible with the Docker plugin of Telegraf.  

Let's create a **SingleStat** in your Panel :

![](/content/images/2016/07/singlestat-grafana.png)

At this point, you can create few nice dashboards showing some interesting information about your containers or your hosts. 

For example, here is a graph of this website bandwidth (managed by docker-compose) :

![](/content/images/2016/07/opsnotice-bandwith.png)

I have finished with this tutorial, I hope it was useful, you can now easily send all your metrics from some Docker hosts to your new Docker supervision Stack.

I suggest you use Grafana behind a TLS reverse-proxy like Nginx. I'm writing an article about that, stay tuned !
<blockquote class="twitter-tweet" data-cards="hidden" data-lang="fr"><p lang="en" dir="ltr">How-to monitor <a href="https://twitter.com/docker">@Docker</a> hosts ? <a href="https://t.co/AWHPOlCybw">https://t.co/AWHPOlCybw</a> by <a href="https://twitter.com/Valentin_NC">@Valentin_NC</a> <a href="https://t.co/8rVOVYwt3Q">pic.twitter.com/8rVOVYwt3Q</a></p>&mdash; Docker (@docker) <a href="https://twitter.com/docker/status/759159080011300864">29 juillet 2016</a></blockquote>
<script async src="//platform.twitter.com/widgets.js" charset="utf-8"></script>

