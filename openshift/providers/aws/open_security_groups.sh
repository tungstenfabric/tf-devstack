#!/bin/bash -e

ports="5995 5995 tcp
6379  6379  tcp
5920  5920  tcp
5921  5921  tcp
4369  4369  tcp
5673  5673  tcp
25673 25673 tcp
15673 15673 tcp
514   514   tcp
6343  6343  tcp
4739  4739  tcp
5269  5269  tcp
53    53    tcp
179   179   tcp
10250 10250 tcp
10256 10256 tcp
80    80    tcp
443   443   tcp
1936  1936  tcp
7000  10000 tcp
2000  3888  tcp
8053  8053  udp
4789  4789  udp
6635  6635  udp"

function set_rules() {
    local group_id=$1
    local rule_cidr="0.0.0.0/0"

    echo "$ports" | while read from to protocol; do
            aws ec2 authorize-security-group-ingress \
                --region "$AWS_REGION" \
                --group-id $group_id \
                --ip-permissions IpProtocol=$protocol,FromPort=$from,ToPort=$to,IpRanges="[{CidrIp=$rule_cidr}]"
    done
}

vpc_id=$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters Name=tag-value,Values=$KUBERNETES_CLUSTER_NAME-* \
    --query Vpcs[0].VpcId)

aws ec2 describe-security-groups \
     --region "$AWS_REGION" \
     --filters Name=vpc-id,Values=$vpc_id \
     --query 'SecurityGroups[?GroupName != `default`].GroupId' | jq -c ".[]" | tr -d \" |
while read group_id; do
     set_rules $group_id
done
