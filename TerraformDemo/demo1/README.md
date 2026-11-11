# OPA Terraform SSH Demo

Read **OPA_Terraform_SSH_Step_by_Step_Guide.docx** first. It contains the complete
walkthrough, expected results, optional tool installation and AWS credential setup,
troubleshooting, recovery, cleanup and official references.

The five working files are unchanged from the demonstrated implementation:

- `main.tf`
- `ssh-after.tfvars`
- `ssh-policy.rego`
- `ssh-policy_test.rego`
- `Invoke-OPATerraform.ps1`

Target: AWS account **503561439433**, region **eu-west-2**.
For an intentionally different account, update `allowed_account_ids` in `main.tf`.
Use a dedicated folder such as `C:\OPA\TerraformDemo`.

No credentials, Terraform state, saved plans or downloaded providers are included.
`terraform init` generates the provider lock file. Retain that file for later runs.

## Quick rehearsal after completing the guide

Run each block separately from the demo folder. Check the result before continuing.

### Check tools and identity

```powershell
terraform version
opa version
aws --version
aws sts get-caller-identity --no-cli-pager
```

### Initialise and test

```powershell
terraform init
if ($LASTEXITCODE -ne 0) { throw "Terraform init failed." }
terraform fmt
if ($LASTEXITCODE -ne 0) { throw "Terraform fmt failed." }
terraform validate
if ($LASTEXITCODE -ne 0) { throw "Terraform validate failed." }
opa test .\ssh-policy.rego .\ssh-policy_test.rego -v
if ($LASTEXITCODE -ne 0) { throw "OPA tests failed." }
Unblock-File .\Invoke-OPATerraform.ps1
```

### Before case

```powershell
terraform plan --out=ssh-before.tfplan
if ($LASTEXITCODE -ne 0) { throw "Before plan failed." }
terraform show .\ssh-before.tfplan
```

```powershell
.\Invoke-OPATerraform.ps1 -PlanFile .\ssh-before.tfplan -Apply
```

Expected: OPA denies the plan; Terraform apply is not run. The terminating red error
is expected. Run the next block separately after observing it.

### After case

```powershell
terraform plan --var-file=ssh-after.tfvars --out=ssh-after.tfplan
if ($LASTEXITCODE -ne 0) { throw "Corrected plan failed." }
.\Invoke-OPATerraform.ps1 -PlanFile .\ssh-after.tfplan
```

Expected: OPA allows the plan; this invocation checks only.

```powershell
.\Invoke-OPATerraform.ps1 -PlanFile .\ssh-after.tfplan -Apply
```

Expected: the allowed saved plan is applied. The fresh demonstration creates a VPC,
security group and SSH rule with source `10.20.30.0/24`. No EC2 instance is launched.
The wrapper exports fresh JSON itself; the full guide also shows the manual JSON
export and OPA evaluation stages for teaching the integration.

### Inspect AWS before cleanup

```powershell
$sgId = terraform output -raw security_group_id
if ($LASTEXITCODE -ne 0) { throw "Cannot read security group ID." }
$ruleQuery = "SecurityGroupRules[].{Egress:IsEgress,Protocol:IpProtocol,"
$ruleQuery += "From:FromPort,To:ToPort,Source:CidrIpv4}"
aws ec2 describe-security-group-rules `
    --region eu-west-2 `
    --filters "Name=group-id,Values=$sgId" `
    --query $ruleQuery `
    --output table --no-cli-pager
```

Expected ingress: TCP, ports 22 to 22, source `10.20.30.0/24`.

### Cleanup

```powershell
terraform destroy --var-file=ssh-after.tfvars
```

Review the proposed deletions and enter `yes`. Then run:

```powershell
terraform state list
```

Expected: no resource addresses. Regenerate the saved plans before the next run.
Plain `terraform destroy` is also valid cleanup for this particular configuration.

The policy covers standalone `aws_vpc_security_group_ingress_rule` resources.
It does not implement an approved-source allowlist or check other security group
resource forms. The wrapper is a local enforcement mechanism; direct Terraform
commands can bypass it when the caller has sufficient AWS permissions.
