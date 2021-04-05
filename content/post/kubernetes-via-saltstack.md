+++
author = "Valentin Ouvrard"
categories = ["docker", "kubernetes", "devops", "saltstack"]
date = 2017-12-25T23:33:32Z
description = ""
draft = true
slug = "kubernetes-via-saltstack"
tags = ["docker", "kubernetes", "devops", "saltstack"]
title = "Kubernetes via Saltstack"

+++


Few weeks ago, I released Kubernetes-Saltstack repo on Github to easily deploy and manage a Kubernetes cluster in production. In this post, I will show you how to simply create a cluster on Digital Ocean VMs but it can be done on any Cloud/Metal provider. 

## I- VMs provisioning
So, we will start to create our machines. We will use latest Ubuntu LTS virtual machines from Digital Ocean in two different data-centers (Singapore and Bangalore). 

We will create 3 master nodes : 

 - master01.myk8s.tld (SIN)
 - master02.myk8s.tld (BAN)
 - master03.myk8s.tld (SIN)

And 3 worker nodes : 

 - worker01.myk8s.tld (SIN)
 - worker02.myk8s.tld (BAN)
 - worker03.myk8s.tld (SIN)

With theses machines, we will be able to get an high-available Kubernetes cluster aware of data-center failure. For sure you can add more worker if needed. In my case I use Asian based locations because I live in the Pacific Ocean.



