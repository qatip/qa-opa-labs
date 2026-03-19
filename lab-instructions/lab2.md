## Lab 2 – Build an OPA Policy from Snippets

© 2026 QA Michael Coulling-Green

### Overview

In this lab, you will construct an OPA policy by selecting from a set of provided Rego snippets.

Each snippet represents a possible policy rule. Some are correct, some are incorrect, and some are irrelevant.

Your goal is to assemble a working policy that enforces the organisation’s governance requirements.

---

### Governance Requirements

All EC2 instances must comply with the following standards:

- Only approved instance types may be used: `t3.micro`, `t3.small`
- All instances must include the following tags:
  - Owner
  - Environment
  - ManagedBy
- Instances must not be configured with a public IP address

---

### Provided Files

- `good/` – compliant Terraform configuration
- `bad/` – non-compliant Terraform configuration
- `policy-chunks/` – available Rego snippets
- `policy.rego` – your working policy file (to be created)

---

### Task

1. Verify Terraform without governance
2. Review the governance requirements above
3. Review the Rego snippets in `policy-chunks/`
4. Identify which snippets enforce the required controls
5. Combine the correct snippets into a single file: policy.rego
6. Verify Terraform with governance


## Lab Flow

This lab is completed in two stages:

### Stage 1 – Terraform Without Governance

In this stage, you will run Terraform normally without any policy enforcement.

Both the compliant and non-compliant configurations will successfully generate a plan.

This demonstrates that Terraform validates infrastructure from a technical perspective only.

---

### Stage 2 – Terraform With OPA Policy Enforcement

In this stage, you will apply an OPA policy to evaluate the Terraform plan.

The compliant configuration will pass validation.

The non-compliant configuration will fail validation.

This demonstrates how OPA enforces organisational governance rules.

## Stage 1 – Terraform Validation Only

### Step 1 – Test the Compliant Configuration

Navigate to the `good/` folder and run:

```bash
terraform init
terraform plan
```

This plan should complete successfully

### Step 2 – Test the Non-Compliant Configuration

Navigate to the `bad/` folder and run:

```bash
terraform init
terraform plan
```

The plan should also complete successfully.

Key Observation

Both configurations are technically valid from Terraform’s perspective.

Terraform does not enforce organisational standards such as naming, tagging, or security policies.

Key Takeaway: `Terraform ensures infrastructure can be created, it does not ensure infrastructure should be created`




