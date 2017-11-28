#!/bin/bash

set -x

kubeadm reset
yum erase -y kubernetes-cni
docker rm -f $(docker ps -a -q)
docker rmi -f $(docker images -q)
kill -9 $(ps -ef| grep docker| grep -v grep| awk '{print $2}')

umount $(cat /proc/mounts| grep docker| awk '{print $1}')
rm -rf /data/docker-runtime /data/docker.log
rm -rf ~/k8s-v1.8.2