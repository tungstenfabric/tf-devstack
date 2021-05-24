#!/bin/bash

set -o errexit

if [ $# -ne 1 ]; then
    echo "Usage: $0 <path-to-imagelist>"
    echo "No imagelist provided or unknown extra arg exist"
    echo "Exiting"
    exit 1
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
listfile=$1

function get_images_from_kubespray() {
    KUBESPRAY_TAG=${KUBESPRAY_TAG:="release-2.14"}
    yum install -y ansible git
    [ ! -d kubespray ] && git clone --depth 1 --single-branch --branch=${KUBESPRAY_TAG} https://github.com/kubernetes-sigs/kubespray.git

    cat << EOF > kubespray/roles/download/tasks/main.yml
- name: gather facts
  gather_facts:

- name: set kubeadm image list
  set_fact:
    kubeadm_images:
      - "k8s.gcr.io/kube-apiserver:{{ kube_version }}"
      - "k8s.gcr.io/kube-controller-manager:{{ kube_version }}"
      - "k8s.gcr.io/kube-scheduler:{{ kube_version }}"
      - "k8s.gcr.io/kube-proxy:{{ kube_version }}"

- name: download | put image repo to list
  lineinfile:
    path: "{{ downloads_file }}"
    line: "{{ item.value.repo }}:{{ item.value.tag }}"
  with_dict: "{{ downloads | combine(kubeadm_images) }}"
  when:
    - item.value.container is defined and item.value.container
    - item.key != 'tiller' or helm_version is version('v3.0.0', '<')

- name: break ansible running here
  fail:
    msg: "No need to run further"
EOF

    cat << EOF > kubespray/inventory/local/hosts.ini
node1 ansible_connection=local local_release_dir={{ansible_env.HOME}}/releases
[kube-master]
node1
[etcd]
node1
[kube-node]
node1
[calico-rr]
node1
[k8s-cluster:children]
kube-node
kube-master
calico-rr
EOF

    cat << EOF > kubespray/get_imagelist.yml
---
- name: Check ansible version
  import_playbook: ansible_version.yml

- hosts: k8s-cluster:etcd
  strategy: linear
  any_errors_fatal: "{{ any_errors_fatal | default(true) }}"
  gather_facts: true
  roles:
    - { role: kubespray-defaults }
    - { role: bootstrap-os, tags: bootstrap-os}
EOF

    cd kubespray
    touch $listfile
    ansible-playbook -i inventory/local/hosts.ini -e downloads_file=$listfile get_imagelist.yml || /bin/true
}

function get_images_for_helm() {
    touch $listfile
    echo "quay.io/airshipit/kubernetes-entrypoint:v1.0.0" >> $listfile
}

rm -f $listfile

get_images_from_kubespray
get_images_for_helm
