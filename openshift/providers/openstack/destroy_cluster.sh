#!/bin/bash -ex

OPENSHIFT_INSTALL_DIR=${OPENSHIFT_INSTALL_DIR:-"os-install-config"}

export INFRA_ID=$(jq -r .infraID $OPENSHIFT_INSTALL_DIR/metadata.json)
if [[ -z "${INFRA_ID}" ]]; then
  echo "ERROR: Something get wrong. You INFRA_ID has not been set up"
  exit 1
fi

if [[ ! -f $OPENSHIFT_INSTALL_DIR/inventory.yaml || ! -f $OPENSHIFT_INSTALL_DIR/common.yaml ]]; then
  echo "INFO: Files inventory.yaml or common.yaml can't be found. It looks like nothing to delete"
  exit 0
fi

openstack image delete bootstrap-ignition-image-$INFRA_ID || /bin/true

if [[ -f ${OPENSHIFT_INSTALL_DIR}/compute-nodes.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy-compute-nodes.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:

  - name: 'Delete Compute servers'
    os_server:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
      delete_fip: yes
    with_indexed_items: "{{ [os_compute_server_name] * os_compute_nodes_number }}"

EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy-compute-nodes.yaml
fi

if [[ -f ${OPENSHIFT_INSTALL_DIR}/servers.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy-control-plane.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Delete the Control Plane servers'
    os_server:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
      delete_fip: yes
    with_indexed_items: "{{ [os_cp_server_name] * os_cp_nodes_number }}"

  - name: 'Delete the Control Plane ports'
    os_port:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
    with_indexed_items: "{{ [os_port_master] * os_cp_nodes_number }}"
  - name: 'Check if server group exists'
    command:
      cmd: "openstack server group show -f value -c name  {{ os_cp_server_group_name }}"
    register: server_group_for_delete
    ignore_errors: True
  - name: 'Delete the Control Plane server group'
    command:
      cmd: "openstack server group delete {{ os_cp_server_group_name }}"
    when: server_group_for_delete.stdout_lines | bool
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy-control-plane.yaml
fi

if [[ -f $OPENSHIFT_INSTALL_DIR/ports.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy_bootstrap.yaml
- import_playbook: common.yaml
- hosts: all
  gather_facts: no

  tasks:
  - name: 'Remove the bootstrap server'
    os_server:
      name: "{{ os_bootstrap_server_name }}"
      state: absent
      delete_fip: yes
  - name: 'Remove kube api LB'
    os_server:
      name: "{{ os_api_lb_server_name }}"
      state: absent
      delete_fip: no
  - name: 'Remove ingress LB'
    os_server:
      name: "{{ os_ing_lb_server_name }}"
      state: absent
      delete_fip: no
  - name: 'Remove the bootstrap server port'
    os_port:
      name: "{{ os_port_bootstrap }}"
      state: absent
  - name: 'Delete the Control Plane ports'
    os_port:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
    with_indexed_items: "{{ [os_port_master] * os_cp_nodes_number }}"
  - name: 'Delete Compute ports'
    os_port:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
    with_indexed_items: "{{ [os_port_worker] * os_compute_nodes_number }}"
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy_bootstrap.yaml
fi

if [[ -f $OPENSHIFT_INSTALL_DIR/network.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy_network.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Delete the Ingress port'
    os_port:
      name: "{{ os_port_ingress }}"
      state: absent
  - name: 'Delete the API port'
    os_port:
      name: "{{ os_port_api }}"
      state: absent
  - name: 'Delete external router'
    os_router:
      name: "{{ os_router }}"
      state: absent
  - name: 'Delete a subnet'
    os_subnet:
      name: "{{ os_subnet }}"
      state: absent
  - name: 'Delete the cluster network'
    os_network:
      name: "{{ os_network }}"
      state: absent
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy_network.yaml
fi
