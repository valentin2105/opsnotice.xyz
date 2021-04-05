+++
author = "Valentin Ouvrard"
categories = ["debian", "linux", "tips", "system"]
date = 2016-07-26T09:09:39Z
description = ""
draft = false
slug = "fix-debian-locales-error"
tags = ["debian", "linux", "tips", "system"]
title = "Fix Debian locales error"

+++


![](/content/images/2016/07/debian-locales.png)

Sometimes, Debian installations have some troubles with locales when you're using apt for example. It is caused by missing environment variables or missing locales configuration. 

![](/content/images/2016/07/locales-errors.png)

To fix this problem for ever, just do these two things :

Add these lines on **.bashrc** or **.zshrc** :
```langage-bash
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```
Then you can run these commands :
```langage-bash
locale-gen en_US.UTF-8
dpkg-reconfigure locales
```
The last command ask you to choose any locale, I use **en_US.UTF-8** in my case. 
You need to restart your shell to apply your environment variables. 

The problem is fixed !

