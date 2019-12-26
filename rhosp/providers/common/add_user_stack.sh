#!/bin/bash

sudo adduser stack
sudo bash -c 'echo "stack           ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers'
sudo mkdir /home/stack/.ssh
sudo bash -c 'echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqFitjdvlQlaVJ8oBTkm3Qt48XCNh8ikbYN38WofGJk5oGXtC35H9eBBJ8giv42Lw4JXzBmVSEceMPEmTnIM3JPEhl/uNgn+Y+0e+pInq6bt3+DjjZxLvhun7G3LP8RgwYMvMWUkNEHnwLaCKipjfzrPkp0uD/1ZQVjY799gSyDX2PylneiLNSSWQxvOwNe8dzLyVTxlS2jFzNmMX5I5a9/z2Dw9PTB8FdFQbAKc7ZqaiYBrp3kaTcBlQh2pRpKEGGhosKhp4DPHoQV/f3myfl3sAZNGfpbFLzBxLyY/nHIJ3w2AsWahxKnxdGSxhmmp5KJ6zl4+OhJdNZEb2glK2l gleb@dell" > /home/stack/.ssh/authorized_keys'
sudo chmod 700 /home/stack/.ssh
sudo chmod 644 /home/stack/.ssh/authorized_keys
sudo chown -R stack:stack /home/stack/.ssh
sudo bash -c 'echo "stack:qwe123QWE" | chpasswd'

