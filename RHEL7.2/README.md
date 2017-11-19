# Kubernetes on RHEL s390x

Here is a `k8s-RHEL-s390x.sh` bash for [Kubernetes](https://kubernetes.io/)' one key deployment on IBM Z (s390x).

## How to use

```bash
$ git clone https://github.com/xuchenhao001/Kubernetes-s390x.git
$ cd Kubernetes-s390x/RHEL7.2
$ chmod +x k8s-RHEL-s390x.sh
$ ./k8s-RHEL-s390x.sh
```

As while as you see :

```bash
*****************************************
Kubernetes v1.8.3 installed successfully!
*****************************************
```

You can access the dashboard from the browser at `https://<your.rhel.host.ip>:31117`. Enter the user name `admin` with password `admin` to log in as a **Administrator**.