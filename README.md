# Info
- This repo creates kubernetes cluster in aws.
- It creates 3 ec2 instances , 1 -controlplabe & 2-worker nodes.

# prerequisites
- configured aws credentials in the repo secrets

# Run the workflow

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





