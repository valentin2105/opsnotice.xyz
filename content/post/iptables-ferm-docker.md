+++
author = "Valentin Ouvrard"
categories = ["docker", "linux", "devops"]
date = 2017-05-08T23:22:48Z
description = ""
draft = false
slug = "iptables-ferm-docker"
tags = ["docker", "linux", "devops"]
title = "IPTables  IPv4/6 for Docker"

+++


Docker use IPTables to create network isolation between containers, to NAT traffic from their private networks and to expose ports on your Docker host. It's why manage a firewall in front of that is not easy as 1,2,3, even more if you use dual stack (IPv4/6) on your containers. 

![](/content/images/2017/05/firewall.png)

To facilitate the control of Docker host's firewall, I use [Ferm](http://ferm.foo-projects.org/), a great Perl front-end for IPtables. You can for sure use the great and simple UFW but Ferm got a more declarative way to write your firewall rules. 

You can install Ferm quickly with your favorite package manager (apt, yum...). Then, all your configurations are placed in **/etc/ferm/**. For example, this is a basic **ferm.conf** :

```
table filter {
    chain INPUT {
        policy DROP;
        mod state state INVALID DROP;
        mod state state (ESTABLISHED RELATED) ACCEPT;
        interface lo ACCEPT;
        proto icmp icmp-type echo-request ACCEPT;

        # our services to the world
        proto tcp dport (ssh http https) ACCEPT;
    }

    chain OUTPUT policy ACCEPT;
    chain FORWARD policy DROP;
}
```
Create a Ferm configuration file for a Docker host is a bit more complicated because we need to manage NAT and isolation for our containers. 

A point of start is to disable IPtables management for your Docker host because you will replace these rules with Ferm (and any reload will erase Docker's rules). 

I will use dual-stack (IPv4/6) for Docker, so we need an IPv6 range defined, for that, if you can't route a Public IPv6 network to your Docker host, you can use a [unique local addresses](https://en.wikipedia.org/wiki/Unique_local_address)  range from [RFC4193](https://tools.ietf.org/html/rfc4193 ) like **fd00::/64**. It's recommended to [generate your own](http://unique-local-ipv6.com/)IPv6 unique local addresses and to not use the same of this example.  

To begin, we must create **/etc/docker/daemon.json** :
```
{
	  "ipv6": true,
	  "fixed-cidr-v6": "fd00::/64",
	  "dns": ["8.8.8.8", "8.8.4.4"],
	  "iptables": false
} 
```
Then restart Docker with a `service docker restart`.

With this, Docker will stop to use IPtables and enable IPv6 with your defined range. So every container created will take an IP address from this range (if no other defined). 


Now, we can create our **/etc/ferm/ferm.conf** :

```
# -*- shell-script -*-
#
#  Configuration file for ferm(1).
#
# Chain policies

# We define our Docker IPv4/6 ranges
@def $DOCKER_RANGE      = (172.16.0.0/12 fd00::/64);

# We drop INPUT/FORWARD by default and ACCEPT output
domain (ip ip6) {
 table filter {
  chain (INPUT FORWARD) policy DROP;
  chain OUTPUT policy ACCEPT;
 }
}

# Loopback
domain (ip ip6) table filter {
 chain INPUT interface lo ACCEPT;
 chain OUTPUT outerface lo ACCEPT;
}

# ICMP (kernel does rate-limiting)
domain (ip) table filter chain (INPUT OUTPUT) protocol icmp ACCEPT;
domain (ip6) table filter chain (INPUT OUTPUT) protocol icmpv6 ACCEPT;

# Invalid
domain (ip ip6) table filter chain INPUT mod state state INVALID DROP;

# Established/related connections
domain (ip ip6) table filter chain (INPUT OUTPUT) mod state state (ESTABLISHED RELATED) ACCEPT;

# We define our opened ports
domain (ip ip6) table filter chain INPUT {
		# SSH
		proto tcp dport ssh ACCEPT;
		# HTTP
		proto tcp dport http ACCEPT;
}

# Docker IPv4 config
domain ip {
  table filter {
    chain FORWARD {
        saddr @ipfilter($DOCKER_RANGE) ACCEPT;
        daddr @ipfilter($DOCKER_RANGE) ACCEPT;
    }
  }
  # Create MASQUERADE for IPv4 ranges
  table nat {
        chain POSTROUTING {
	         saddr @ipfilter($DOCKER_RANGE)  MASQUERADE;
        }
    }
}

# Docker IPv6 config
domain ip6 {

table filter {
  chain FORWARD {
      saddr @ipfilter($DOCKER_RANGE) ACCEPT;
      daddr @ipfilter($DOCKER_RANGE) ACCEPT;
  }
}

# Create MASQUERADE for Docker IPv6 unique local addresses ranges
# Delete this rules if you use Public IPv6 network. 
table nat {
      chain POSTROUTING {
          saddr @ipfilter($DOCKER_RANGE)  MASQUERADE;
      }
  }
}

```

Now we can reload the Ferm firewall with a small `/etc/init.d/ferm/reload`

If you use a public IPv6 range routed to your server, you need to remove the latest block that enables IPv6 NAT (not required in full public IPv6 networking).

We will try to launch a Nginx docker containers and reach them on the port 80 of our Docker host. This port is open due to the line that say : `proto tcp dport http ACCEPT` :

```
docker run -d --restart always --name nginx -p 80:80 nginx:alpine

docker exec nginx ifconfig

eth0      Link encap:Ethernet  HWaddr 02:42:AC:11:00:02  
          inet addr:172.17.0.2  Bcast:0.0.0.0  Mask:255.255.0.0
          inet6 addr: fd00::242:ac11:2/64 Scope:Global

docker exec -it nginx sh
/ # ping6 google.com
PING google.com (2404:6800:4003:c00::64): 56 data bytes
64 bytes from 2404:6800:4003:c00::64: seq=0 ttl=47 time=46.374 ms

root@docker-host:~# curl [::]80
<!DOCTYPE html>
```

You can try to reach the port 80 on IPv4 then on IPv6, it would normally work correctly. You can try to reboot your Docker host to check if the rules are persistent. If you try to launch a container to port 8080, you can't access to him without specifying it on your **ferm.conf** file.

That all ! Now you got a fully firewalled Docker host. 

**BONUS**: If you use IPv4 only, here is a gist of the **[ferm.conf](https://gist.github.com/valentin2105/63afec4027546b28e998e3b6e1727195)**.

