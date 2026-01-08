# This repository is to lauch kubernetes cluster on AWS EC2 instances using Terraform
# Once the instances are launched configure kubernetes standalone cluster using ansible

# Deploy control plane and 2 worker nodes on AWS
cd ./Ansible-ec2-standalone-kubernetes-cluster/
terraform init, plan and apply.

# Launch Kubernetes cluster on the standalone machines
cd k8s-ansible
--  update the inventory.ini file 
ansible-playbook control-plane.yml
ansible-playbook workers.yml

# check the cluster
- login to cp using ssh
- kubectl get nodes 
- kubectl get pods --all-namespaces

# configure cluster to access locally 
- generate certificate with publicIP on control plane
sudo rm /etc/kubernetes/pki/apiserver.{crt,key}
sudo kubeadm init phase certs apiserver --apiserver-cert-extra-sans=<CONTROLPLANE_PUBLIC_IP>
sudo kubeadm init phase certs apiserver --apiserver-cert-extra-sans=18.234.195.183
- For containerd (standard in newer versions)
sudo crictl ps | grep kube-apiserver | awk '{print $1}' | xargs sudo crictl stop


- On your local machine
ssh -i my-terraform-key ubuntu@<CONTROLPLANE_PUBLIC_IP> 'sudo cat /etc/kubernetes/admin.conf' > ./kubeconfig
ssh -i my-terraform-key ubuntu@18.234.195.183 'sudo cat /etc/kubernetes/admin.conf' > ./kubeconfig

- change public IP in ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig

- Allow inbound traffic on security group port 6443 of ControlPlane

# test cluster
kubectl get nodes

################
## for one liner quick from the branch 
terraform init
terraform apply -auto-approve && cd k8s-ansible && ansible-playbook -i inventory.ini control-plane.yml workers.yml



