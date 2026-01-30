# AWS Kubernetes Cluster via Terraform & Ansible

This repository automates the deployment of a Kubernetes cluster on AWS EC2 instances. It utilizes Terraform for infrastructure provisioning and Ansible for Kubernetes installation and configuration, all orchestrated via GitHub Actions.

## Architecture Overview
- Infrastructure: 3 EC2 Instances (Ubuntu).
   * 1 Control Plane Node.
   * 2 Worker Nodes.
- Provisioning: Terraform with S3/DynamoDB remote state.
- Configuration: Ansible playbooks for K8s setup.
- CI/CD: GitHub Actions workflow for automated apply and destroy

## Prerequisites
Before running the workflow, ensure you have the following ready:
- AWS Credentials: A user with programmatic access and permissions for EC2, VPC, S3, and DynamoDB
- GitHub Secrets: Add the following to your repository secrets:
    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * SSH_PUBLIC_KEY: Used by Terraform to authorize access to instances.
    * SSH_PRIVATE_KEY: Used by Ansible to connect and configure the nodes.

## Setup Backend (Manual)
 ### Create S3 Bucket
aws s3 mb s3://backed-bucket-1187 --region us-east-1

 ### Create DynamoDB Table for State Locking
aws dynamodb create-table \
  --table-name terraform-lock-table \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1

## Deployment
The cluster is managed via the GitHub Actions tab:
- Navigate to the Actions tab in your repository.
- Select the Manage Kubernetes Cluster workflow.
- Click Run workflow.
- Choose apply to build or destroy to tear down the infrastructure.

## Post-Deployment: Accessing the Cluster
Once the workflow finishes, you can verify and access your cluster.

### 1. Internal Check (SSH)
ssh -i <your-key> ubuntu@<CONTROLPLANE_PUBLIC_IP>
kubectl get nodes
kubectl get pods --all-namespaces

### 2. External Check (Local Machine)
To manage the cluster from your local terminal, you must update the API Server certificate to include the public IP.
- On the Control Plane
    #### Regenerate certificates with Public IP
    * sudo rm /etc/kubernetes/pki/apiserver.{crt,key}
    * sudo kubeadm init phase certs apiserver --apiserver-cert-extra-sans=<CONTROLPLANE_PUBLIC_IP>

    #### Restart the API Server (Containerd)
    * sudo crictl ps | grep kube-apiserver | awk '{print $1}' | xargs sudo crictl stop

- On your Local Machine:
    #### Download the config
    * ssh -i <your-key> ubuntu@<CONTROLPLANE_PUBLIC_IP> 'sudo cat /etc/kubernetes/admin.conf' > ./kubeconfig
      * (Example- (ssh -i "my-terraform-key" ubuntu@44.203.176.129 'sudo cat /etc/kubernetes/admin.conf' > ./kubeconfig))

    #### Update the server IP in the file to the Public IP

    #### Then export the path
    * export KUBECONFIG=$PWD/kubeconfig

    #### Optional: Move to default location
    * cp kubeconfig ~/.kube/config

## Project Structure
- / : HCL files for AWS resources.
- /k8s-ansible: Playbooks for Docker/Containerd, Kubeadm, and CNI initialization.
- .github/workflows: The YAML definition for the CI/CD pipeline.
