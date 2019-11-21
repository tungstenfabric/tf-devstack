#!/bin/bash

if [ -d "/etc/kubernetes" ]; then
  sudo kubeadm reset -f --cert-dir /etc/kubernetes/ssl || sudo kubeadm reset --cert-dir /etc/kubernetes/ssl
  sudo rm -rf \
    /var/lib/etcd \
    /etc/kubernetes \
    /etc/ssl/etcd \
    /etc/etcd
  sudo service kubelet stop
  sudo service etcd stop
fi
sudo docker rm -f $(sudo docker ps -a -q)
sudo docker container prune -f
