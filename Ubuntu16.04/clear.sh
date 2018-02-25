#!/bin/bash

set -x

kubeadm reset

rm -rf ~/.kube
rm -rf ~/k8s-v*

