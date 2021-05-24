#!/bin/bash

if [ $# -ne 1  ]; then
    echo "Usage: $0 <path-to-store-image-list>"
    echo "No path provided, exiting"
    exit 1
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cat "my_dir/thirdparty_images.list" > $1
