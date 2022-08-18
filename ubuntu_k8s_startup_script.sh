#!/bin/bash

# enabling bridge traffic
lsmod | grep br_netfilter
modprobe br_netfilter

# copying be_netfilter config into k8s.conf
cat << EOF | tee /etc/modules-load.d/k8s.conf
be_netfilter
EOF

# copying ip_tables rules into k8s.conf
cat << EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# applying changes
sysctl --system

# removing an old versions of docker
apt remove -y docker docker-cli docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine docker docker-engine docker.io containerd runc

# adding repo of kubernetes and docker
apt update && apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# docker instalarion
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# removing depricated config file
rm /etc/containerd/config.toml
systemctl restart containerd

# configuring Docker Daemon for cgroups management and run docker
cat << EOF | tee /etc/docker/daemon.json
{
	"exec-opts" : ["native.cgroupdriver=systemd"],
	"log-driver" : "json-file",
	"log-opts" : {
		"max-size" : "1000m"
	},
	"storage-driver" : "overlay2"
}
EOF

# docker as a daemon enabling
systemctl daemon-reload
systemctl restart docker
systemctl enable docker
systemctl status docker

# kubelet, kubeadm, kubectl installation
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt install -y kubelet kubeadm kubectl

# enabling kubelet as a daemon
systemctl enable --now kubelet

# kubernetes cluster master node initialization
kubeadm init --pod-network-cidr=10.10.0.0/16 --apiserver-advertise-address=$(hostname -I | cut -d" " -f1)

# installing CNI-plugin (Weave) for POD networking
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
