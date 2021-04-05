+++
author = "Valentin Ouvrard"
categories = ["kubernetes", "docker", "cluster"]
date = 2017-08-16T23:27:54Z
description = "How-to make your Kubernetes experience easier, secure and reproducible, especially on premise cluster"
draft = false
slug = "kubernetes-tips-tricks"
tags = ["kubernetes", "docker", "cluster"]
title = "Kubernetes tips & tricks"

+++


In this post, we will see few points to make your Kubernetes experience easier, secure and reproducible, especially on premise cluster. 

![](/content/images/2017/08/banner.png)

### I- Deploy using helm
![](/content/images/2017/08/Screen-Shot-2017-08-16-at-08.53.38.png)

Helm is described as a packets manager for Kubernetes. It allows you to package all your application specifications to easily redeploy on any cluster. 

A basic helm repository is composed by :

 - `Charts.yaml` for the name, tags and version of your application
 - `templates/` is the folder where you put all your Kubernetes .yaml files (deployments, services, ingresses...)
 - `values.yaml` is a key-value .yaml file where you put all the variables that you want to use in your templates' files. 

For example, if you got this `values.yaml` :
```
global:
  dbName: test
  dbPassword: xahc5Ceej2keekoo
```

You can use theses variables in your `templates/mysql-deployment.yaml` file :

```
apiVersion: v1
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: mysql
  namespace: default
  labels:
    k8s-app: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: mysql
  template:
    metadata:
      labels:
        k8s-app: mysql
    spec:
      containers:
      - image: mysql:latest
        name: mysql
        imagePullPolicy: Always
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: {{ .Values.global.dbPassword }}
        - name: MYSQL_DATABASE
          value: {{ .Values.global.dbName }}
``` 
To install your own helm chart, you can use this command :
```
helm install --name=my-chart /chart-folder
```
If  you make a change in your chart (manually or via CI), you can update it with this command :
```
helm upgrade my-chart /chart-folder
```
### II- Expose your services with Ingresses

There are many ways to expose a service in a Kubernetes cluster. If you don't use a cloud hosted cluster, you couldn't use the `LoadBalancer` type because nobody will provide you a public IP address. 

The best way, for me, in a production-wide cluster, is to use an `Ingress Controller` like `Nginx Ingress` and to expose it via service's `External IPs`.

To make it possible, you need to route a public (or private) IP range on your k8s' workers and then you can create services like this :
```
apiVersion: v1
kind: Service
metadata:
  labels:
    svc: controller
  name: controller
  namespace: default
spec:
  clusterIP: 10.32.35.129
  externalIPs:
  - 101.5.124.76
  ports:
  - port: 80
    protocol: TCP
    targetPort: 8888
  selector:
    svc: controller
  type: ClusterIP

```
The external IP is then `caught` by workers' IPTables who NAT the traffic to the final Pod. If you do this for your Nginx Ingress service, you can now expose all your internal services behind one unique public IPv4 (and IPv6 soon). 

If you think about High-availability, you need to share an IP between all your k8s workers (like `keepalived`) to route your Public IP's to it. (only on premise cluster). 

### III- Use TLS everywhere
To make your internal cluster communications' secures, it's a good point to use TLS in every deployment you create. 

The first point is to expose your pod's service with TLS directly, so if you use a http only server in your container, why not configure TLS with embedded certificates. 

The last point is to expose your TLS service to the Internet with full TLS encryption. So if you use an Ingress controller to expose your service, you need to create first, a TLS secret : 
```
kubectl -n default create secret tls pod1-tls --key privkey.pem --cert fullchain.pem
```
Then, you can create your TLS Ingress resource :
```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: pod1
  namespace: default
  annotations:
    nginx.org/ssl-services: "pod1"
    kubernetes.io/ingress.class: "nginx"
spec:
  tls:
  - hosts:
    - pod1.example.com
    secretName: pod1-tls
  rules:
  - host: pod1.example.com
    http:
      paths:
      - path: /
        backend:
          serviceName: pod1
          servicePort: 443
```
As you see, The service `pod1` is fully exposed with TLS. 

### IV- Use Calico for Network policies
![](/content/images/2017/08/Project-Calico-logo-1000px.png)

`Calico` is a tool that enables `Secure networking for the cloud native era`. 
It is compatible with Kubernetes that allows many awesome options like :
  
 - Fine-grained networking policy
 - Routed networking between workers
 - BGP with core routers if want to totally disable NAT
 - IPv6 on pods (really soon)
 - Multiple IP Pools

And many other folks !

If you got a Kubernetes cluster with Calico, you can enable isolation in a namespace with this command :
```
kubectl annotate ns my-namespace "net.beta.kubernetes.io/network-policy={\"ingress\":{\"isolation\":\"DefaultDeny\"}}"

```
For example, you can create a Nginx pod/service on `my-namespace`. Nobody can talk to him because the namespace is annoted with `DefaultDeny`. 
If you want to allow the access to your Nginx, you need to define this rule with a `NetworkPolicy` like this :  

```
kind: NetworkPolicy
apiVersion: extensions/v1beta1
metadata:
  name: access-nginx
  namespace: my-namespace
spec:
  podSelector:
    matchLabels:
      run: nginx
  ingress:
    - from:
      - podSelector:
          matchLabels: {}
```
So, with that, you can clearly define in your cluster, which pod can speak to which other pod. If you want to install Calico in your Kubernetes cluster, please take a look to [the documentation](https://docs.projectcalico.org/v2.4/getting-started/kubernetes/)

### V- GlusterFS for painless volumes
If you don't use a cloud providers who provide volume plugin for Kubernetes (AWS or Google Cloud), you will need to create your own external volume providers for your cluster. 

`GlusterFS` is a tool that allows to share data (volumes) between two or more Linux servers and to use them in your Kubernetes cluster. 

You can find a lot of posts about how to make a GlusterFS cluster. When you achieve this, here is how to use it in your Kubernetes installation :

First, you will need to install `glusterfs-client` on each worker.

After that, you need to get a `Endpoint` in the desired namespace :
```
{
  "kind": "Endpoints",
  "apiVersion": "v1",
  "metadata": {
    "name": "glusterfs-cluster",
    "namespace": "default"
  },
  "subsets": [
    {
      "addresses": [
        {
          "ip": "10.240.0.100"
        }
      ],
      "ports": [
        {
          "port": 1
        }
      ]
    }
  ]
}
```
and a `Service` in the same namespace :
```
{
  "kind": "Service",
  "apiVersion": "v1",
  "metadata": {
    "name": "glusterfs-cluster",
    "namespace": "default"
  },
  "spec": {
    "ports": [
      {"port": 1}
    ]
  }
}
```
Now, with theses resources, you can use the name `glusterfs-cluster` as a volume provider. Here is an example of a MariaDB pod :
```
      containers:
      - image: mariadb:latest
        name: mariadb
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: DiThoshePh6oe45fezfz
        volumeMounts:
        - name: db-folder
          mountPath: /var/lib/mysql
      volumes:
        - name: db-folder
          glusterfs:
            endpoints: glusterfs-cluster
            path: gluster-volume-name
            readOnly: false
```

### VI- Install k8s dashboard
The Kubernetes dashboard is a nice UI to see your cluster's status. It is quite easy to deploy in a new or existing cluster, just follow theses steps : 
```
kubectl create -f https://git.io/kube-dashboard
```
When all pods are created, you can access the dashboard using `kubectl proxy`:
```
kubectl proxy
http://127.0.0.1:8001/ui
```
![](/content/images/2017/08/Screen-Shot-2017-08-16-at-08.07.38.png)
### VII- Use RBAC
RBAC (Roles based authentification control) is the perfect way to clearly define who can access to what in your cluster. 
To enable RBAC in a Kubernetes cluster, you need to set this flag in the `kube-apiserver` configuration (Caution, it can break something in running cluster): 
```
  --authorization-mode=RBAC
```
When RBAC is enabled and you want to get admin users, you can put them in the `system:masters` group (highest admin level). 

To create, for example, an user `developer` restricted to the `dev` namespaces, you will need to create a `Role` and a `RoleBinding` ressource :
```
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  namespace: dev
  name: role-developer
rules:
- apiGroups: ["*"] # "" indicates the core API group
  resources: ["*"]
  verbs: ["*"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rolebinding-developer
  namespace: dev
subjects:
- kind: User
  name: developer
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: role-developer
  apiGroup: rbac.authorization.k8s.io
```
RBAC allow you to clearly define your users authorization. To go more deeper in RBAC in Kubernetes I suggest you read the [official documentation](https://kubernetes.io/docs/admin/authorization/rbac/).

### VIII- Follow your deployment logs
`Kubetail` is a small bash script that allow you to follow logs of every pod in a  Kubernetes deployment. 
```
wget https://raw.githubusercontent.com/johanhaleby/kubetail/master/kubetail
chmod +x kubetail && mv kubetail /usr/local/bin
```
Imagine you got a deployment called `nginx` and scaled to 10 pods, you can follow the 10 pods' logs with this command :
```
kubetail nginx -n my-namespace
```

### IX- Clean your cluster !
Continues deployment on top of a Kubernetes cluster is great but it creates a lot of old Docker images who, if you do nothing, grow and grow on your Workers file-system. 

A good practice, to avoid Linux problem on Docker host, is to use a dedicated partition for the Docker folder (default `/var/lib/docker`). 

A second point is to automate worker's cleanup (delete old images) with cron, configuration manager or a better approach, by [Kubelet directly](https://kubernetes.io/docs/concepts/cluster-administration/kubelet-garbage-collection/).

If you use `Deployment` on Kubernetes, be sure to use `.spec.revisionHistoryLimit` to limit `ReplicaSets` history on your cluster. If you don't do this, you can get quickly more than 100 old `ReplicaSets`.



> That all for now !

