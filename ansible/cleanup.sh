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
sudo docker rmi $(sudo docker images)
sudo docker volume rm $(sudo docker volume ls)
sudo rm -rf /etc/contrail/
sudo rm -rf /var/log/contrail
sudo rm -rf /home/centos/contrail-kolla-ansible
rm -rf ~/.tf/.stages
