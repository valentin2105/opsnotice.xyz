+++
author = "Valentin Ouvrard"
categories = ["docker", "cluster", "devops", "kubernetes"]
date = 2016-12-15T23:09:38Z
description = ""
draft = true
slug = "h-a-kubernetes-with-calico"
tags = ["docker", "cluster", "devops", "kubernetes"]
title = "H/A Kubernetes with Calico"

+++


----------------
<img class="size-full wp-image-1570 aligncenter" src="https://blog.ouvrard.it/wp-content/uploads/2016/12/kubernetes-banner.png" alt="" width="555" height="250" />

In this post, we will create a high-available Kubernetes cluster from scratch (without using a all-in-one script or cloud-provider) configuring all components and use TLS certs for secure communications of them.

We will use Calico, a full layer 3 virtual networking plugin for Kubernetes using BGP, the protocol used by a great network, Internet.

## 1. Preparation of the environment


We will try to create a near *prod-ready* cluster. For this, he will have to be high-available, encrypted and fault tolerant. This article is not full presentation of all Kubernetes components, so you can, for sure, refere to the official documentation. 

In this tutorial, we will create :

- 3 ETCD servers who will create a quorum which contain all datas about our Kubernetes cluster.
- 3 Master servers who will host the APIServer and other Kubernetes components.
- 3 Worker servers where Docker will run our containers.

For add more ressources to our cluster, you will just had to add some Worker servers on your k8s cluster. 

In this post, I will use some virtual machines because its quite simply to deploy (on a data-center or on your own laptop). I will use **Ubuntu 16.04 LTS**. For sure, you can deploy the same configuration on bare-metal server or on anything who can run a x64 Linux OS. 

So, we will create 9 virtual machines with 2Go RAM for ETCD and Masters and why not go until 8 or 16 Go for our Workers. If it's for testing, this ressources will be a bit expensive, you can for sure, deploy theses configuration with a single ETCD and Master VM or puth both on the same machine. If you want to deploy a single node cluster for testing, you can take a look at my small deployment script : (Kubernetes_Deployment)

<img src="https://blog.ouvrard.it/wp-content/uploads/2016/12/HA-Kubernetes.png" alt="" width="256" height="414" class="size-full aligncenter wp-image-1581" />

Our 9 servers : 

- etcd0.example.com - 10.240.0.10/24
- etcd1.example.com - 10.240.0.11/24
- etcd2.example.com - 10.240.0.12/24
- master0.example.com - 10.240.0.20/24
- master1.example.com - 10.240.0.21/24
- master2.example.com - 10.240.0.22/24
- worker0.example.com - 10.240.0.30/24
- worker1.example.com - 10.240.0.31/24
- worker2.example.com - 10.240.0.32/24

About the network, our servers are present in the same 10.240.0.0/24 with a gateway in 10.240.0.1. This network allow us to add 253 servers in or near our cluster. 

I let you the pleasure to create your virtual servers with your favorite hypervisor and then, configure your server with a minimal secure configuration (updates, ssh-key ...). In my case, I use Xen and Ganeti for provision my VMs and Saltstack for manage configuration. 

I have wrote some Salt configuration file for Kubernetes If it interests someone. 

## Certs generation


To ensure the encryption of the data that passes between our machines, we will implement TLS between each element of the cluster.
To properly generate and sign our certificates, we will use a Cloudflare CfSSL tool, which allows you to manage an internal certification authority, but you can also use OpenSSL as described in the <a href="http://(https://coreos.com/kubernetes/docs/latest/openssl.html" target="_blank">CoreOS documentation</a>. 

For communications in the cluster, I will use the hostname of the machines rather than their IPs to facilitate future network renumbering.

To do this, 3 options are available to you:

- Add name / IP correspondence in your internal DNS
- Replace the hostname with the corresponding IP in the following configurations
- Use a distributed / etc / hosts file between your VMs (my option).

For start, we need the CfSSL tool : 

```
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64

chmod +x cfssl_linux-amd64

sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl

wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64

chmod +x cfssljson_linux-amd64

sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
```
We then place ourselves in a folder called `certs` and we generate and sign our certificates after creating a CA :

```
mkdir /root/certs ; cd /root/certs

echo '{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}' > ca-config.json

echo '{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NC",
      "L": "Noumea",
      "O": "Kubernetes",
      "OU": "Cluster",
      "ST": "Province-Sud"
    }
  ]
}' > ca-csr.json


cfssl gencert -initca ca-csr.json | cfssljson -bare ca


cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "worker0.example.com",
    "worker1.example.com",
    "worker2.example.com",
    "etcd0.example.com",
    "etcd1.example.com",
    "etcd2.example.com",
    "master0.example.com",
    "master1.example.com",
    "master2.example.com",
    "10.32.0.1",
    "127.0.0.1"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "NC",
      "L": "Noumea",
      "O": "Kubernetes",
      "OU": "Cluster",
      "ST": "Province-Sud"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes
  
KUBERNETES_HOSTS=(etcd0 etcd1 etcd2 worker0 worker1 worker2 manager0 manager1 manager2)
  
for host in ${KUBERNETES_HOSTS[*]}; do
  scp ca.pem  ${host}:~/
  scp kubernetes-key.pem  ${host}:~/
  scp kubernetes.pem ${host}:~/
done

```
Do not forget to adapt these commands with the data specific to your cluster (hostnames or IPs, numbers of machines ...). The `kubernetes-csr.json` file must know all the hostnames or IPs allowed to use these certificates. The last command copies SSH all your certificates to the machines that require them.

You should have theses files :

```
- ca-key.pem
- ca.pem
- kubernetes-key.pem
- kubernetes.pem
```
Maintenant que nos certificats sont correctement générés et déployés sur nos machines, on va pouvoir passer à l'installation des composants de Kubernetes. 

Dans l'optique d'une mise en production, il faudra bien sûr générer un certificat propre à chaque élément du cluster et non un pour tout le cluster. Il faudra également prévoir un renouvellement de l'autorité de certification, car celle-ci à une durée d'un an.  

## Mis en place d'ETCD
ETCD est une base de données clé-valeur distribuée créée par CoreOS, un élément essentiel à Kubernetes puisqu'il y stocke toute les informations de votre cluster, comme quel container tourne sur quel Worker et quel service porte quelle IP. 

S’il faut donc qu'un service soit hautement disponible et sauvegardé, c'est bien lui. 

Nous allons donc installer et configurer ETCD en cluster. Ces commandes sont donc à réaliser sur nos 3 VMs ETCD : 

```
sudo mkdir -p /etc/etcd/

sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

wget https://github.com/coreos/etcd/releases/download/v3.0.15/etcd-v3.0.15-linux-amd64.tar.gz

tar -xvf etcd-v3.0.15-linux-amd64.tar.gz

sudo mv etcd-v3.0.15-linux-amd64/etcd* /usr/bin/

sudo mkdir -p /var/lib/etcd
```

On peut désormais créer le fichier unit systemD qui lancera ETCD avec les bons arguments : 


```
cat > etcd.service <<"EOF"
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/bin/etcd --name ETCD_NAME \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --initial-advertise-peer-urls https://INTERNAL_IP:2380 \
  --listen-peer-urls https://INTERNAL_IP:2380 \
  --listen-client-urls https://INTERNAL_IP:2379,http://127.0.0.1:2379 \
  --advertise-client-urls https://INTERNAL_IP:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster etcd0=https://etcd0.example.com:2380,etcd1=https://etcd1.example.com:2380,etcd2=https://etcd2.example.com:2380 \
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv etcd.service /etc/systemd/system/
```

Veillez à remplacer `INTERNAL_IP` par l'IP de votre machine ETCD.

On peut ensuite lancer notre service ETCD :

```
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
```

Une fois cela réalisé sur nos 3 VMs, on peut vérifier la santé de notre cluster comme ceci : 

```
etcdctl --ca-file=/etc/etcd/ca.pem cluster-health
```

Maintenant que notre ETCD est répliqué, chiffré et en bonne santé, on va pouvoir monter notre Kubernetes sur cette base. 

## Mis en place des Masters

Un Master Kubernetes comporte 3 composants différents : 

- L'API Server fournit une API REST structurée pour interroger et envoyer des informations dans notre cluster ETCD.
- Le Scheduler permet de répartir les pods sur les Workers du cluster.
- Le Controller Manager s'assure que les ressources désirées tournent bien dans notre cluster.

Je vous invite à lire la documentation pour comprendre de manière plus détaillée les fonctions et possibilités qu'offre chaque élément. 

D'un point de vue réseau, Kubernetes offre plusieurs possibilités. Dans mon exemple nous allons donc utiliser le plugin CNI de Flannel permettant de définir dynamiquement un range d'IP par Worker pour nos containers qui passeront par un bridge nommé `cbr0`. Nous allons lui donner dans la configuration le range 10.200.0.0/16 et il découpera un /24 pour chaque Worker (exemple : worker1 = 10.200.1.0/24). 

Nos services (manière d'exposer un ou plusieurs containers derrière un couple IP/hostname) doivent également avoir un range d'IP propre à eux, nous utiliserons 10.32.0.0/16 permettant d'avoir jusqu'à 65 536 IPs de services. L'accès aux IPs de services est géré de manière dynamique sur les Workers grâce à des règles IPTables piloté par Kubernetes (kube-proxy).

Nous allons donc récupérer ces éléments dans leur dernière version (v1.4.7) et les configurer correctement avec des fichiers d'units systemD.

Vous pouvez bien sûr remplacer le numéro de version dans les liens par celle que vous souhaitez installer, car Kubernetes est relativement jeune et les nouvelles versions sortent rapidement.  

Voici les dernières releases : <a href="https://github.com/kubernetes/kubernetes/releases/" target="_blank">https://github.com/kubernetes/kubernetes/releases/</a>

Vous devez réaliser ces étapes sur chacune des VMs Masters :

```
sudo mkdir -p /var/lib/kubernetes

sudo cp ca.pem kubernetes-key.pem kubernetes.pem /var/lib/kubernetes/

wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kube-apiserver
wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kube-controller-manager
wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kube-scheduler
wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kubectl

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl

sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/bin/

cat > kube-apiserver.service <<"EOF"
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/bin/kube-apiserver \
  --admission-control=NamespaceLifecycle,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota \
  --advertise-address=INTERNAL_IP \
  --allow-privileged=true \
  --apiserver-count=3 \
  --authorization-mode=ABAC \
  --authorization-policy-file=/var/lib/kubernetes/authorization-policy.jsonl \
  --bind-address=0.0.0.0 \
  --enable-swagger-ui=true \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --insecure-bind-address=0.0.0.0 \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --etcd-servers=https://etcd0.example.com:2379,https://etcd1.example.com:2379,https://etcd2.example.com:2379 \
  --service-account-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --service-cluster-ip-range=10.32.0.0/16 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --token-auth-file=/var/lib/kubernetes/token.csv \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-apiserver.service /etc/systemd/system/

sudo systemctl daemon-reload

sudo systemctl enable kube-apiserver


cat > kube-controller-manager.service <<"EOF"
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/bin/kube-controller-manager \
  --allocate-node-cidrs=true \
  --cluster-cidr=10.200.0.0/16 \
  --cluster-name=kubernetes \
  --leader-elect=true \
  --master=http://INTERNAL_IP:8080 \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --service-cluster-ip-range=10.32.0.0/16 \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


sudo mv kube-controller-manager.service /etc/systemd/system/

sudo systemctl daemon-reload

sudo systemctl enable kube-controller-manager

cat > kube-scheduler.service <<"EOF"
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/bin/kube-scheduler \
  --leader-elect=true \
  --master=http://INTERNAL_IP:8080 \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-scheduler.service /etc/systemd/system/

sudo systemctl daemon-reload

sudo systemctl enable kube-scheduler
```
Remplacez bien les occurrences de `INTERNAL_IP` par l'adresse IP de la machine correspondante. 

Pour accéder à notre API Server, cela se fera en HTTPS sur le port 6443 et en HTTP en local uniquement sur le port 8080. Afin de s'identifier auprès de l'API, Kubernetes utilise un système de tokens.

On créé donc le fichier `/var/lib/kubernetes/token.csv` sur chacune de nos machines contenant des tokens aléatoires pour chacun de nos utilisateurs :

```
prA5ahie3ohtoo4boogvre6quipheaTh,admin,admin
FWiephivof8onershoong1thee8tosoj,valentin,valentin
hbgith7aWi1aegheifeRhdaiLahVie3z,kubelet,kubelet
```

On va ensuite créer le fichier `/var/lib/kubernetes/authorization-policy.jsonl` également sur tous nos Masters :

```
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"*", "nonResourcePath": "*", "readonly": true}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"admin", "namespace": "*", "resource": "*", "apiGroup": "*"}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"valentin", "namespace": "*", "resource": "*", "apiGroup": "*"}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"scheduler", "namespace": "*", "resource": "*", "apiGroup": "*"}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"kubelet", "namespace": "*", "resource": "*", "apiGroup": "*"}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"group":"system:serviceaccounts", "namespace": "*", "resource": "*", "apiGroup": "*", "nonResourcePath": "*"}}
```

N'oubliez pas d'adapter le nom de vos users dans ce fichier. Celui-ci permet de définir les autorisations de chaque utilisateur dans notre cluster.

On va pouvoir enfin démarrer notre Cluster Kubernetes : 

```
sudo systemctl start kube-apiserver

sudo systemctl start kube-controller-manager

sudo systemctl start kube-scheduler
```

Pour vérifier que tout va bien dans notre cluster, on peut utiliser l'outil `kubectl` téléchargé précédemment :

```
kubectl get componentstatuses

NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok                   
scheduler            Healthy   ok                   
etcd-1               Healthy   {"health": "true"}   
etcd-0               Healthy   {"health": "true"}   
etcd-2               Healthy   {"health": "true"} 
```
Vous avez désormais une installation dite High-available de Kubernetes. Cependant, nous n’avons pour l'instant aucun serveur Docker branché à notre cluster, donc il ne sert pas à grand-chose.

## Mis en place des Workers
Un Worker Kubernetes se compose de trois éléments, un gestionnaire de containers comme Docker et Rkt (de coreOS) qui s'occupe de lancer et gérer vos containers, Kubelet qui est un élément propre à Kubernetes permettant de piloter vos containers, vos images, vos volumes (...) et Kube-Proxy qui s'occupe de gérer l'iptables de votre Worker afin de router les IPs de services vers les bons pods. 

Dans ce post, on va se consacrer à Docker, mais promis je reparlerais bientôt de Rkt. 

On va donc récupérer Docker en version 1.12.3, Kubelet et Kube-proxy sur chacun de nos Workers et les configurer par la suite :

```
sudo mkdir -p /var/lib/kubernetes

sudo cp ca.pem kubernetes-key.pem kubernetes.pem /var/lib/kubernetes/

wget https://get.docker.com/builds/Linux/x86_64/docker-1.12.3.tgz

tar -xvf docker-1.12.3.tgz

sudo cp docker/docker* /usr/bin/

sudo sh -c 'echo "[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
ExecStart=/usr/bin/docker daemon \
  --iptables=false \
  --ip-masq=false \
  --host=unix:///var/run/docker.sock \
  --log-level=error \
  --storage-driver=overlay
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/docker.service'
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl start docker
sudo docker version


sudo mkdir -p /opt/cni

wget https://storage.googleapis.com/kubernetes-release/network-plugins/cni-07a8a28637e97b22eb8dfe710eeae1344f69d16e.tar.gz

sudo tar -xvf cni-07a8a28637e97b22eb8dfe710eeae1344f69d16e.tar.gz -C /opt/cni

wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kube-proxy
wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kubelet

chmod +x kubectl kube-proxy kubelet

sudo mv kubectl kube-proxy kubelet /usr/bin/

sudo mkdir -p /var/lib/kubelet/

sudo sh -c 'echo "apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /var/lib/kubernetes/ca.pem
    server: https://master0.example.com:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubelet
  name: kubelet
current-context: kubelet
users:
- name: kubelet
  user:
    token: hbgith7aWi1aegheifeRhdaiLahVie3z" > /var/lib/kubelet/kubeconfig'

sudo sh -c 'echo "[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/kubelet \
  --allow-privileged=true \
  --api-servers=https://master0.example.com:6443,https://master1.example.com:6443,https://master2.example.com:6443 \
  --cloud-provider= \
  --cluster-dns=10.32.0.10 \
  --cluster-domain=cluster.local \
  --configure-cbr0=true \
  --container-runtime=docker \
  --docker=unix:///var/run/docker.sock \
  --network-plugin=kubenet \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --reconcile-cidr=true \
  --serialize-image-pulls=false \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/kubelet.service'

sudo systemctl daemon-reload

sudo systemctl enable kubelet

sudo systemctl start kubelet

sudo sh -c 'echo "[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/bin/kube-proxy \
  --master=https://master0.example.com:6443 \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --proxy-mode=iptables \
  --v=2

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/kube-proxy.service'

sudo systemctl daemon-reload

sudo systemctl enable kube-proxy

sudo systemctl start kube-proxy    
```

Comme nous avons défini un range d'IPs en /24 par Worker, il faut que nos containers puissent passer d'un Worker à un autre afin de se parler entre eux (exemple : une application et sa base de donnée peuvent être sur deux Workers différents). Pour cela, il faut que nous Workers ait une route vers chacun de ses voisins. 

Vous pouvez gérer cela de manière dynamique avec un gestionnaire de configuration (comme Salt ou Ansible), ou simplement ajouter les routes à la main sur chacun des Workers : 

```
ip route add 10.200.0.0/24 via 10.240.0.30

ip route add 10.200.1.0/24 via 10.240.0.31

ip route add 10.200.2.0/24 via 10.240.0.32
```

Il faudra cependant ne pas oublier d'ajouter une route à chaque fois qu'on ajoute un Worker au cluster.

Nos Workers sont désormais prêts et reliés à notre cluster Kubernetes, pour vérifier cela, on se connecte à une de nos VMs Masters et on saisit cette commande :

```
kubectl get nodes
```

## Configuration du client kubectl

Kubectl est l'outil en ligne de commande permettant de piloter notre cluster Kubernetes. Comme les autres composants, il va se connecter de manière chiffrée à notre API Server, il faut donc posséder le certificat client sur la machine ou l'on souhaite configurer kubectl. Il vous faudra également le Token qui correspond à votre utilisateur, qu'on a créé plus haut.

Sur nos VMs Masters, kubectl est installé et n’a pas besoin d'authentification comme ils communiquent en local. Vous pouvez donc effectuer les prochaines étapes depuis un Master plutôt que de configurer un client externe. 

On va donc récupérer l'outil Kubectl pour Linux ou pour Mac :

```
## Mac
wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/darwin/amd64/kubectl

## Linux
wget https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kubectl

chmod +x kubectl
sudo mv kubectl /usr/local/bin

kubectl config set-cluster my-prod-cluster \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://master0.example.com:6443
  
  
kubectl config set-credentials admin --token prA5ahie3ohtoo4boogvre6quipheaTh

kubectl config set-context default-context \
  --cluster=my-prod-cluster \
  --user=admin

kubectl config use-context default-context

kubectl get componentstatuses

kubectl get nodes

NAME      STATUS    AGE
worker0   Ready     7m
worker1   Ready     5m
worker2   Ready     2m
```
## Mis en place du DNS Interne (kube-dns)

Notre cluster est désormais fonctionnel et hautement disponible avec 3 workers Docker prêts à recevoir nos applications et à les scaller à volonté. Cependant, nos pods (un groupe de containers sur une même IP) ont bien accès à Internet, mais n'ont pas de résolution DNS externe et interne. 

Pour régler ce problème, nous allons déployer le service SkyDNS afin d'avoir de la résolution en interne dans le cluster sur l'IP de service 10.32.0.10 qui permettra de résoudre dynamiquement les noms de nos services afin de pouvoir utiliser des hostnames plutôt que des IPs. (Par exemple, dans la configuration de la base de données pour site Wordpress, vous mettrait "mysql-wordpress" plutôt que l'IP du service qui elle, peut changer). 

```
echo "

apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kube-dns-v20
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    version: v20
    kubernetes.io/cluster-service: "true"
spec:
  replicas: 3
  selector:
    matchLabels:
      k8s-app: kube-dns
      version: v20
  template:
    metadata:
      labels:
        k8s-app: kube-dns
        version: v20
        kubernetes.io/cluster-service: "true"
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
        scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly", "operator":"Exists"}]'
    spec:
      containers:
      - name: kubedns
        image: gcr.io/google_containers/kubedns-amd64:1.8
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        livenessProbe:
          httpGet:
            path: /healthz-kubedns
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8081
            scheme: HTTP
          # we poll on pod startup for the Kubernetes master service and
          # only setup the /readiness HTTP server once that's available.
          initialDelaySeconds: 3
          timeoutSeconds: 5
        args:
        # command = "/kube-dns"
        - --domain=example.com
        - --dns-port=10053
        ports:
        - containerPort: 10053
          name: dns-local
          protocol: UDP
        - containerPort: 10053
          name: dns-tcp-local
          protocol: TCP
      - name: dnsmasq
        image: gcr.io/google_containers/kube-dnsmasq-amd64:1.4
        livenessProbe:
          httpGet:
            path: /healthz-dnsmasq
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        args:
        - --cache-size=1000
        - --no-resolv
        - --server=127.0.0.1#10053
        - --log-facility=-
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
      - name: healthz
        image: gcr.io/google_containers/exechealthz-amd64:1.2
        resources:
          limits:
            memory: 50Mi
          requests:
            cpu: 10m
            memory: 50Mi
        args:
        - --cmd=nslookup kubernetes.default.svc.example.com 127.0.0.1 >/dev/null
        - --url=/healthz-dnsmasq
        - --cmd=nslookup kubernetes.default.svc.example.com 127.0.0.1:10053 >/dev/null
        - --url=/healthz-kubedns
        - --port=8080
        - --quiet
        ports:
        - containerPort: 8080
          protocol: TCP
      dnsPolicy: Default
---
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: KubeDNS
  name: kube-dns
  namespace: kube-system
  resourceVersion: "223165"
spec:
  clusterIP: 10.32.0.10
  ports:
  - name: dns
    port: 53
    protocol: UDP
    targetPort: 53
  - name: dns-tcp
    port: 53
    protocol: TCP
    targetPort: 53
  selector:
    k8s-app: kube-dns
  sessionAffinity: None
  type: ClusterIP

" | kubectl create -f -
```
Ce déploiement de Kube-DNS va créer un pod de 3 containers par Worker afin de permettre une résolution de nom des services propres au cluster et de fournir de la résolution de nom externe pour nos containers. 

On vérifie que tout est bien créé : 

```
kubectl get pod --all-namespaces


kube-system     kube-dns-v20-3504276524-6xon3                3/3       Running   0         1d       10.200.0.229   worker0.example.com
kube-system     kube-dns-v20-3504276524-vcmag                3/3       Running   0          1d       10.200.2.122   worker2.example.com
kube-system     kube-dns-v20-3504276524-wzaae                3/3       Running   0          1d       10.200.1.237   worker1.example.com
```

Pour être sûr que la résolution DNS fonctionne, on va tester avec un petit pod Busybox, bien pratique :

```
kubectl run -i -t busybox --image=busybox --restart=Never


/ # nslookup google.com
Server:    10.32.0.10
Address 1: 10.32.0.10 kube-dns.kube-system.svc.k8.noc.nc

Name:      google.com
Address 1: 2404:6800:4006:807::200e syd09s13-in-x0e.1e100.net
Address 2: 61.5.222.166
```

## Accès externe aux services

L'accès externe aux services est une problématique assez complexe dans l'univers de Kubernetes, car elle permet plusieurs approches. Dans le cas d'un cluster GKE, le type de services LoadBalancer permet de demander une IP publique pour exposer notre service. C'est pratique, mais nous, on  l'a monté nous même notre cluster, donc pas de mécanisme de provisionning d'IP publiques. 

Plusieurs choix s'offrent à vous : 

- Utiliser le type NodePort qui expose un service sur un port élevé de tous vos Workers. Cela peut être pratique pour tester le bon fonctionnement de son service, mais plus complexe pour mettre en place un reverse-proxy.
- Utiliser une IP publique dans le champ ExternalIPs d'un service. Cela est une approche très pratique, mais il faut avoir des IP publiques routées vers nos Worker, donc pas possibles dans un environnement de test. 
- Utiliser un Ingress controller comme Traefik ou Nginx Ingress controller et de les exposer en mode NodePort sur les ports 80/443 de nos Workers. Cela permet de définir des noms d'accès à nos services (Ingress), l'équivalent d'un VirtualHost, et qu'un reverse proxy les servent dynamiquement et de manière chiffrée (TLS). Je détaillerai cette installation dans un futur article. 

## Smoke tests

Pour vérifier que tout fonctionne, on va se créer un petit déploiement avec 3 replicas pour voir si Kubernetes répartit bien les containers sur tous nos Workers. Nous l'exposerons ensuite en mode NodePort. 

```
kubectl run nginx --image=nginx --port=80 --replicas=3

kubectl expose deployment nginx --type NodePort

NODE_PORT=$(kubectl get svc nginx --output=jsonpath='{range .spec.ports[0]}{.nodePort}')

curl http://worker0.example.com:${NODE_PORT}

<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```
Notre déploiement de Nginx est exposé en mode NodePort sur tous nos Workers et load-balance entre 3 replicas reparties sur nos serveurs Docker. 

Voilà, c'est fini pour aujourd'hui. Nous avons donc monté un cluster hautement disponible et qui communique de manière chiffrée. Une petite chose à améliorer cependant, il est préférable selon moi d'utiliser un outil comme Keepalived sur les machines Masters afin d'avoir une IP partagée entre ces 3 machines. Cela permet d'être totalement tolérant à l'extinction de 2 VMs sur 3. Actuellement certains services (kube-proxy ou kubelet) dépendant d'une seule API-Server. 

Dans un prochain article, je vous expliquerai comment ajouter des add-ons à notre cluster afin d'avoir entre autres, le dashboard Kubernetes, Grafana pour les métriques et Kibana pour les logs de notre cluster. Nous mettrons en place Nginx Ingress Controller et Kube-lego pour exposer nos services en HTTPS avec Let's Encrypt. Puis nous verrons comment utiliser les outils Kompose, pour convertir des fichiers Docker-compose en déploiement Kubernetes et Helm qui est en quelque sorte un package manager d'application pour Kubernetes. Je vous ferais également un article pour parler des mécanismes de volumes externes à Kubernetes comme GlusterFS qui permettent d'avoir les données des containers externalisés des Workers. 

Je remercie tout particulièrement <a href="https://twitter.com/kelseyhightower" target="_blank">Kelsey Hightower</a> pour son dépôt "<a href="https://github.com/kelseyhightower/kubernetes-the-hard-way" target="_blank">Kubernetes-The-Hard-Way</a>" qui m'a franchement bien aidé et  Mikaël Cluseau qui m'a supporté dans mes longues interrogations autour de ce fabuleux tools qu'est Kubernetes.

