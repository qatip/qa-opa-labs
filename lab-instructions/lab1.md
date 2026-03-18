# Lab 2 – OPA with Kubernetes

© 2026 QA Michael Coulling-Green

# Lab Overview

In this lab, you will use OPA as a Gatekeeper for a Kubernetes cluster
Rather than manually building the kubernetes infrastructure, you will deploy a pre-defined environment. Having deployed the environment, you will deploy and test the OPA Gatekeeper against a development K8S cluster.

# Lab Steps

Ensure you have cloned the class repo onto your IDE machine into c:\qa-opa-labs.

Instructions assume the repo is at c:\qa-opa-labs, adjust all paths as necessary 

## Create an EC2 Key Pair (Windows + PowerShell)

The automated build deploys virtual machines that allow remote connectivity using a pem key. The key to be used must first be created and downloaded.
1.	Log into the AWS console using your lab credentials
2.	In AWS Console: EC2 → Key Pairs → Create key pair.
3.	Key type: RSA. File format: .pem.
4.	Name it "my-keypair" and download the PEM file.
5.	Move the downloaded PEM file to your home directory .ssh folder
6.	Fix permissions to prevent any OpenSSH issues (update with your user name)...
<p>

```bash
icacls C:\Users\YourUserName\.ssh\my-keypair.pem /inheritance:r
icacls C:\Users\YourUserName\.ssh\my-keypair.pem /grant:r "$($env:USERNAME):(R)"
```

</p>

7. Provision the remote environment using Terraform
<p>

```bash
cd c:\qa-opa-labs\k8s-opa\bootstrap
terraform init
terraform apply --auto-approve
```

</p>

8.	Terraform will output the public IP of two virtual machines, a GitOps host running K8S, ArgoCD and AWX and an Automation host running Jenkins…


## SSH to the GitOps Host and Verify Bootstrap

9.	SSH from PowerShell, updating gitops-public-ip with that shown in output for GitOps host:

</p>

```bash
ssh -i ~/.ssh/my-keypair.pem ubuntu@gitops-public-ip
```

</p>


10.	Watch the log as the deployment progresses:

</p>

```bash
sudo tail -n 200 /var/log/kind_install.log
```

</p>

11.	You may have to wait for logging to commence. Re-run the above command periodically as the script progresses. Wait until you see the completion banner indicating the bootstrap finished …
 
12.	Once completed, confirm K8S clusters exist

</p>

```bash
sudo kind get clusters
```

</p>

Expect to see three clusters; dev, platform and prod

13. Confirm kubectl contexts exist

</p>

```bash
kubectl config get-contexts
```

</p>

Expect to see three contexts; kind-dev, kind-platform and kind-prod

14. Confirm nodes are Ready in each cluster

</p>

```bash
kubectl --context kind-platform get nodes
kubectl --context kind-dev get nodes
kubectl --context kind-prod get nodes
```

</p>

Expected to see three nodes; platform-control-plane, dev-control-plane and prod-control-plane. All nodes should be Ready
 
Cleanup (Optional)
32.	To remove the lab infrastructure when instructed:
terraform destroy --auto-approve
Note: destroying the host will remove all kind clusters and installed controllers.
