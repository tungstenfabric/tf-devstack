#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

OS="$1"

if [[ -z "$OS" ]]; then
  echo "ERROR: please run as 'prepare_image.sh {ubuntu|centos}"
  exit 1
fi

# NOTE 1:
# please install 'sudo apt install libguestfs-tools'

# NOTE 2:
# libguestfs: warning: current user is not a member of the KVM group (group ID 118).
# This user cannot access /dev/kvm, so libguestfs may run very slowly. It is recommended
# that you 'chmod 0666 /dev/kvm' or add the current user to the KVM group (you might need
# to log out and log in again)."

echo "INFO: downloading image"
case $OS in
  ubuntu)
    SERIES=${SERIES:-bionic}
    if [[ "$SERIES" == 'bionic' ]]; then
      BASE_IMAGE_NAME="ubuntu18"
      name='bionic-server-cloudimg-amd64.img'
    else
      echo "ERROR: unsupported series $SERIES"
      exit 1
    fi
    wget -nv https://cloud-images.ubuntu.com/$SERIES/current/$name -O ./$BASE_IMAGE_NAME.qcow2
    ;;
  centos)
    BASE_IMAGE_NAME="centos7"
    wget -nv https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-2009.qcow2 -O ./$BASE_IMAGE_NAME.qcow2
    ;;
  *)
    echo "ERROR: please run as 'prepare_image.sh {ubuntu|centos}"
    exit 1
    ;;
esac

source ${my_dir}/functions.sh
source ${my_dir}/definitions

if ! get_pool_path $BASE_IMAGE_POOL ; then
  create_pool $BASE_IMAGE_POOL
fi
pool_path=$(get_pool_path $BASE_IMAGE_POOL)

# makepasswd --clearfrom=- --crypt-md5 <<< 'qwe123QWE'
# $1$PU257S1Q$hdOk0pm6Yu7URJRNLQa7e1
SSH_KEY=$HOME/.ssh/id_rsa.pub

if ! lsmod |grep '^nbd ' ; then
  modprobe nbd max_part=8
fi
nbd_dev="/dev/nbd0"
sudo qemu-nbd -d $nbd_dev || true
sudo qemu-nbd -n -c $nbd_dev ./$BASE_IMAGE_NAME.qcow2
sleep 5
ret=0
tmpdir=$(mktemp -d)
sudo mount ${nbd_dev}p1 $tmpdir || ret=1
sleep 2

# patch image
pushd $tmpdir
# disable metadata requests
echo 'datasource_list: [ None ]' | sudo tee etc/cloud/cloud.cfg.d/90_dslist.cfg > /dev/null
# enable root login
sudo sed -i -e 's/^disable_root.*$/disable_root: 0/' etc/cloud/cloud.cfg
# set root password: 123
sudo sed -i -e 's/^root:[!\*]*:/root:$1$PU257S1Q$hdOk0pm6Yu7URJRNLQa7e1:/' etc/shadow
# add ssh keys for root account
sudo mkdir -p root/.ssh
cat $SSH_KEY | sudo tee root/.ssh/authorized_keys > /dev/null
cat $SSH_KEY | sudo tee root/.ssh/authorized_keys2 > /dev/null
popd

sudo umount ${nbd_dev}p1 || ret=2
sleep 2
sudo rm -rf $tmpdir || ret=3
sudo qemu-nbd -d $nbd_dev || ret=4
sleep 2

truncate -s 60G temp.raw
sudo virt-resize --expand /dev/vda1 $BASE_IMAGE_NAME.qcow2 temp.raw
qemu-img convert -O qcow2 temp.raw $BASE_IMAGE_NAME.qcow2
rm temp.raw

virsh vol-delete --pool $BASE_IMAGE_POOL $BASE_IMAGE_NAME || /bin/true
virsh vol-create-as $BASE_IMAGE_POOL $BASE_IMAGE_NAME $(stat -Lc%s $BASE_IMAGE_NAME.qcow2) --format raw
virsh vol-upload --pool $BASE_IMAGE_POOL $BASE_IMAGE_NAME $BASE_IMAGE_NAME.qcow2
virsh vol-info --pool $BASE_IMAGE_POOL $BASE_IMAGE_NAME
