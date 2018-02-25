#!/bin/bash

# Written by Chenhao Xu

# Install kubernetes with kubeadm v1.9.3 on Ubuntu16.04 s390x
# You need a good network environment.
# Please run this bash on root
# Test passed on LinuxONE Community Cloud

set -e

# Kubernetes version
K8S_VERSION=v1.9.3

# Clear firewall rules
echo -e "\n\n********************\nClear firewall rules\n********************\n\n"
iptables -F
echo "Done!"

# Turn off swap
echo -e "\n\n*************\nTurn off swap\n*************\n\n"
swapoff -a
free -h
echo -e "\nDone!"

# Install docker
echo -e "\n\n**************\nInstall docker\n**************\n\n"
apt-get update
apt-get install -y docker.io
echo -e "Done!"

# Install kubeadm
echo -e "\n\n***************\nInstall kubeadm\n***************\n\n"
apt-get update && apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
echo -e "\nDone!"

# Install k8s cluster by kubeadm
echo -e "\n\n******************************\nInstall k8s cluster by kubeadm\n******************************\n\n"
mkdir ~/k8s-${K8S_VERSION}
kubeadm reset
kubeadm init --kubernetes-version ${K8S_VERSION} --pod-network-cidr=10.244.0.0/16
mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
kubectl taint nodes --all node-role.kubernetes.io/master-
echo -e "\nDone!"

# Install flannel
echo -e "\n\n***************\nInstall flannel\n***************\n\n"
wget -P ~/k8s-${K8S_VERSION}/ https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
sed -i "s/amd64/s390x/g" ~/k8s-${K8S_VERSION}/kube-flannel.yml
kubectl apply -f ~/k8s-${K8S_VERSION}/kube-flannel.yml
echo -e "\nDone!"

# Install Kubernetes dashboard
echo -e "\n\n*****************\nInstall dashboard\n*****************\n\n"
wget -P ~/k8s-${K8S_VERSION}/ https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
sed -i "s/amd64/s390x/g" ~/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "/targetPort: 8443/a\\      nodePort: 31117\n  type: NodePort" ~/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "/--auto-generate-certificates/a\\          - --authentication-mode=basic" ~/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
kubectl apply -f ~/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
echo -e "Done!"

# Create user/password authentication & authorization for k8s
echo -e "\n\nCreate user/password\n********************\n"
echo "admin,admin,admin" >/etc/kubernetes/pki/basic_auth.csv
sed -i "/etcd-servers/a\\    - --basic-auth-file=\/etc\/kubernetes\/pki\/basic_auth.csv" /etc/kubernetes/manifests/kube-apiserver.yaml
systemctl restart kubelet
echo -e "Done!"

# Waiting for apiserver reload basic-auth config
echo -e "\n\nWaiting for apiserver running"
APISERVERSTATUS=$(ps -ef| grep apiserver| grep basic-auth-file| wc -l)
until [ "${APISERVERSTATUS}" == "1" ]; do
  sleep 10
  printf "*"
  APISERVERSTATUS=$(ps -ef| grep apiserver| grep basic-auth-file| wc -l)
done
echo -e "\n\nDone!"

echo -e "\n\nWaiting for pods running"
PODSSTATUS=$(kubectl get pods -n kube-system 2>/dev/null| grep Running| wc -l)
until [ "${PODSSTATUS}" == "8" ]; do
  sleep 10
  printf "*"
  PODSSTATUS=$(kubectl get pods -n kube-system 2>/dev/null| grep Running| wc -l)
done
echo -e "\n"
cat <<EOF >  ~/k8s-${K8S_VERSION}/custom-rbac-role.yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: custom-cluster-role
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: User
  name: admin
  namespace: kube-system
EOF
kubectl create -f ~/k8s-${K8S_VERSION}/custom-rbac-role.yaml

# Fix firewall drop rule
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

echo -e "\n\n*****************************************"
echo -e "Kubernetes ${K8S_VERSION} installed successfully!"
echo -e "*****************************************\n\n"

