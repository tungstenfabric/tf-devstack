
#Creating rhsm.yaml from template 
for i in `echo $RHEL_REPOS`; do sed -i "/rhsm_repos:/ a \ \ \ \ \ \ - $i" cat $my_dir/rhsm.yaml.template; done #inserting repos  
#Getting orgID
export RHEL_ORG_ID=$(sudo subscription-manager identity | grep "org ID" | sed -e 's/^.*: //')

cat $my_dir/rhsm.yaml.template | envsubst > ~/rhsm.yaml


