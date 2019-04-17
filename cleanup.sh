#!/bin/bash

if [ -d "/etc/kubernetes" ]; then
  kubeadm reset -f --cert-dir /etc/kubernetes/ssl || sudo kubeadm reset --cert-dir /etc/kubernetes/ssl
  rm -rf /var/lib/etcd
  rm -rf /etc/kubernetes
  rm -rf /etc/ssl/etcd
  rm -rf /etc/etcd
  service kubelet stop
  service etcd stop
fi
docker rm -f $(docker ps -a -q)
docker container prune -f
