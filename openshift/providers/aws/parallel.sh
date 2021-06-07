#!/bin/bash

# This script is using in parallel way with `openshift-install create cluster`
my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"

success=false

for i in {1..60}; do
    sleep 60
    security_groups_count="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filter Name="tag-key",Values="*$KUBERNETES_CLUSTER_NAME*" --query "SecurityGroups[*]" | jq length)"
    if [ "$security_groups_count" -ge "3" ]; then
    # In the setup terraform creates 3 security groups
        $my_dir/open_security_groups.sh
        success=true
        break
    fi
done

[[ success == false ]] && exit 1

success=false

for i in {1..60}; do
    sleep 60
    if oc -n openshift-ingress get service router-default 1>/dev/null 2>/dev/null; then
        oc -n openshift-ingress patch service router-default --patch '{"spec": {"externalTrafficPolicy": "Cluster"}}'
        success=true
        break
    fi
done

[[ success == false ]] && exit 1
exit 0
