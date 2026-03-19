output "automation_host_public_ip" {
  description = "Public IP of the Automation Host (Jenkins/AWX VM)"
  value       = aws_instance.automation_host.public_ip
}

output "gitops_host_public_ip" {
  description = "Public IP of the GitOps Host (kind + ArgoCD VM)"
  value       = aws_instance.gitops_host.public_ip
}

output "automation_host_ssh" {
  description = "SSH command for the Automation Host"
  value       = "ssh -i ~/.ssh/my-keypair.pem ubuntu@${aws_instance.automation_host.public_ip}"
}

output "gitops_host_ssh" {
  description = "SSH command for the GitOps Host"
  value       = "ssh -i ~/.ssh/my-keypair.pem ubuntu@${aws_instance.gitops_host.public_ip}"
}

output "argocd_admin_password" {
  description = "Initial Argo CD admin password configured on the GitOps host."
  value       = var.argocd_admin_password
  sensitive   = true
}