#!/bin/bash

# Written by Chenhao Xu

# Install kubernetes with kubeadm v1.8.2 on RHEL7.2 s390x
# You need a good network environment.
# Please run this bash on root
# Test passed on LinuxONE Community Cloud

set -e

# Kubernetes version
K8S_VERSION=v1.8.3

# Clear firewall rules
echo -e "\n\n********************\nClear firewall rules\n********************\n\n"
iptables -F
echo "Done!"

# Turn off swap
echo -e "\n\n*************\nTurn off swap\n*************\n\n"
swapoff -a
free -m
echo -e "\nDone!"

# Install docker
echo -e "\n\n**************\nInstall docker\n**************\n\n"
yum install -y ebtables ethtool
wget ftp://ftp.unicamp.br/pub/linuxpatch/s390x/redhat/rhel7.3/docker-17.05.0-ce-rhel7.3-20170523.tar.gz
tar -zxf docker-17.05.0-ce-rhel7.3-20170523.tar.gz
cp ./docker-17.05.0-ce-rhel7.3-20170523/docker* /usr/bin/
mkdir -p /data
nohup dockerd -s overlay --data-root /data/docker-runtime > /data/docker.log 2>&1 &
rm -rf docker-17.05.0-ce-rhel7.3-20170523 docker-17.05.0-ce-rhel7.3-20170523.tar.gz
echo -e "Done!"

# Install kubeadm
echo -e "\n\n***************\nInstall kubeadm\n***************\n\n"
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-s390x
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
    https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
set +e
setenforce 0
set -e
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
sed -i "s/--cgroup-driver=systemd/--cgroup-driver=cgroupfs/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
echo -e "\nDone!"

# Install k8s cluster by kubeadm
echo -e "\n\n******************************\nInstall k8s cluster by kubeadm\n******************************\n\n"
mkdir $HOME/k8s-${K8S_VERSION}
kubeadm reset
systemctl start kubelet
kubeadm init --skip-preflight-checks --kubernetes-version ${K8S_VERSION} --pod-network-cidr=10.244.0.0/16
cp -f /etc/kubernetes/admin.conf $HOME/k8s-${K8S_VERSION}
chown $(id -u):$(id -g) $HOME/k8s-${K8S_VERSION}/admin.conf
echo "export KUBECONFIG=$HOME/k8s-${K8S_VERSION}/admin.conf" >> /etc/profile
source /etc/profile
kubectl taint nodes --all node-role.kubernetes.io/master-
echo -e "\nDone!"

# Install flannel
echo -e "\n\n***************\nInstall flannel\n***************\n\n"
wget -P $HOME/k8s-${K8S_VERSION}/ https://raw.githubusercontent.com/coreos/flannel/v0.9.0/Documentation/kube-flannel.yml
sed -i "s/amd64/s390x/g" $HOME/k8s-${K8S_VERSION}/kube-flannel.yml
kubectl apply -f $HOME/k8s-${K8S_VERSION}/kube-flannel.yml
echo -e "\nDone!"

# Install Kubernetes dashboard
echo -e "\n\n*****************\nInstall dashboard\n*****************\n\n"
wget -P $HOME/k8s-${K8S_VERSION}/ https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
sed -i "/Dashboard Secret/,+11s/^/#/" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "/initContainers:/,+5s/^/#/" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "s/amd64/s390x/g" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "/targetPort: 8443/a\\      nodePort: 31117\n  type: NodePort" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "/dashboard.crt/a\\          - --authentication-mode=basic" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
echo -e "Done!"

# Create secrets for dashboard
echo -e "\n\nCreate secrets\n**************\n\n"
mkdir -p $HOME/k8s-${K8S_VERSION}/certs
openssl req -nodes -newkey rsa:2048 -keyout $HOME/k8s-${K8S_VERSION}/certs/dashboard.key -out $HOME/k8s-${K8S_VERSION}/certs/dashboard.csr -subj "/C=/ST=/L=/O=/OU=/CN=kubernetes-dashboard"
openssl x509 -req -sha256 -days 365 -in $HOME/k8s-${K8S_VERSION}/certs/dashboard.csr -signkey $HOME/k8s-${K8S_VERSION}/certs/dashboard.key -out $HOME/k8s-${K8S_VERSION}/certs/dashboard.crt
kubectl create secret generic kubernetes-dashboard-certs --from-file=$HOME/k8s-${K8S_VERSION}/certs -n kube-system
kubectl apply -f $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
echo -e "\nDone!"

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
  sleep 1
  printf "*"
  APISERVERSTATUS=$(ps -ef| grep apiserver| grep basic-auth-file| wc -l)
done
echo -e "\n\nDone!"

echo -e "\n\nWaiting for pods running"
PODSSTATUS=$(kubectl get pods -n kube-system 2>/dev/null| grep Running| wc -l)
until [ "${PODSSTATUS}" == "8" ]; do
  sleep 1
  printf "*"
  PODSSTATUS=$(kubectl get pods -n kube-system 2>/dev/null| grep Running| wc -l)
done
echo -e "\n"
cat <<EOF >  $HOME/k8s-${K8S_VERSION}/custom-rbac-role.yaml
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
kubectl create -f $HOME/k8s-${K8S_VERSION}/custom-rbac-role.yaml

# Fix firewall drop rule
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

echo -e "\n\n*****************************************"
echo -e "Kubernetes v1.8.2 installed successfully!"
echo -e "*****************************************\n\n"