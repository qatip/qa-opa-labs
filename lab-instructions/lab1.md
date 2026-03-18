# Lab 2 – OPA with Kubernetes

© 2026 QA Michael Coulling-Green

# Lab Overview

In this lab, you will use OPA as a Gatekeeper for a Kubernetes cluster
Rather than manually building the kubernetes infrastructure, you will deploy a pre-defined environment. Having deployed the environment, you will deploy and test the OPA Gatekeeper against a development K8S cluster.

## Lab Steps

<details><summary>show command</summary>
<p>

```bash
kubectl run simple --image=public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v1
```

</p>
</details>



Ensure you have cloned the class repo onto your IDE machine into c:\qa-opa-labs.
Instructions assume the repo is at c:\qa-opa-labs, adjust all paths as necessary 
Create an EC2 Key Pair (Windows + PowerShell)
The automated build deploys virtual machines that allow remote connectivity using a pem key. The key to be used must first be created and downloaded.
1.	Log into the AWS console using your lab credentials
2.	In AWS Console: EC2 → Key Pairs → Create key pair.
3.	Key type: RSA. File format: .pem.
4.	Name it "my-keypair" and download the PEM file.
5.	Move the downloaded PEM file to your home directory .ssh folder
6.	Fix permissions to prevent any OpenSSH issues:
icacls C:\Users\<YourUserName>\.ssh\my-keypair.pem /inheritance:r
icacls C:\Users\<YourUserName>\.ssh\my-keypair.pem /grant:r "$($env:USERNAME):(R)"
Provision the remote environment using Terraform
7.	Run the following commands…
cd c:\qa-opa-labs\k8s-opa\bootstrap
terraform init
terraform apply --auto-approve
8.	Terraform will output the public IP of two virtual machines, a GitOps host running K8S, ArgoCD and AWX and an Automation host running Jenkins…


SSH to the GitOps Host and Verify Bootstrap
9.	SSH from PowerShell (replace IP with that shown in output for GitOps host):
ssh -i C:\Users\<YourUserName>\.ssh\gitops-keypair.pem ubuntu@<public-ip>
10.	Watch the log as the deployment progresses:
sudo tail -n 200 /var/log/kind_install.log
11.	You may have to wait for logging to commence. Re-run the above command periodically as the script progresses. Wait until you see the completion banner indicating the bootstrap finished …
 
12.	Once completed, verify bootstrap status …
Confirm kind clusters exist: sudo kind get clusters
Expected:
 
Confirm kubectl contexts: kubectl config get-contexts
Expected: 
 
Confirm nodes are Ready in each cluster:
kubectl --context kind-platform get nodes
kubectl --context kind-dev get nodes
kubectl --context kind-prod get nodes
Expected: 
 
Bootstrap note: your install script provisions Docker, kubectl, kind, the three clusters, Argo CD (NodePort 30080), and AWX (NodePort 30082).
13.	Obtain and note the AWX admin password …
nano awx-password.txt
Use Ctrl+x to exit nano
14.	Obtain and note the ArgoCD  admin password …
nano argo-password.txt
Use Ctrl+x to exit nano
Verify Argo CD
15.	Access Argo CD in your browser: http://<gitops_host_public_ip>:30080
16.	Login using ‘admin’ and the password noted earlier.
17.	Bookmark the ArgoCD url for future use and log out
Verify AWX
18.	Access AWX in your browser: http://<gitops_host_public_ip>:30082
19.	Login using ‘admin’ and the password noted earlier.
20.	Bookmark the AWX url for future use and log out
SSH to the Automation Host and Verify Jenkins Installation
21.	Exit your current SSH session to the GitOps vm; 
exit
22.	SSH from PowerShell (replace public-ip with that shown in output for Automation host):
ssh -i C:\Users\<YourUserName>\.ssh\gitops-keypair.pem ubuntu@<public-ip>
23.	Verify Jenkins is Running
Check the service: sudo systemctl is-active jenkins
Expected output: active
24.	Retrieve the Initial Admin Password…
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
25.	Copy the password and login to Jenkins; http://<automation_host_public_ip>:8080
26.	Paste the initial admin password when prompted.
27.	Click ‘Install suggested plugins’
 
28.	For ‘Create First Admin User’, click to ‘skip and continue as admin’
29.	Click ‘Save and finish’
30.	Click ‘Start using Jenkins’
31.	Bookmark the Jenkins url for future use and log out
Cleanup (Optional)
32.	To remove the lab infrastructure when instructed:
terraform destroy --auto-approve
Note: destroying the host will remove all kind clusters and installed controllers.
