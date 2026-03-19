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

Both configurations are technically valid from Terraform’s perspective.

Terraform does not enforce organisational standards such as naming, tagging, or security policies.

Key Takeaway: `Terraform ensures infrastructure can be created, it does not ensure infrastructure should be created`


## Stage 2 – Apply OPA Policy Enforcement

### Step 1 - Build the Policy

A skeleton `policy.rego` file has been provided in the root of `lab2`.

You are also provided with a set of Rego snippets in: lab2\policy-chunks\

Your task is to select and combine the correct snippets to produce a working policy.

Requirements:

Your completed policy must enforce:

- Approved instance types only (`t3.micro`, `t3.small`)
- Required tags (`Owner`, `Environment`, `ManagedBy`)
- No public IP address on instances

Instructions:

1. Review the snippets in `policy-chunks\`
2. Identify which snippets enforce the required controls
3. Copy the correct snippets into `policy.rego`
4. Ignore any snippets that are incorrect or irrelevant


Challenge:

Not all snippets are valid.

Some:
- target the wrong resource
- contain incorrect logic
- enforce the wrong requirement

Select carefully.

### Step 2 – Validate your Policy

Navigate to the `good/` folder and run:

```bash
terraform plan -out tfplan.binary
terraform show -json tfplan.binary > tfplan.json
```

Run OPA:

```bash
opa eval -f pretty -d ../policy.rego -i tfplan.json "data.terraform.aws.deny"
```
Expected result: `[]`

Navigate to the `bad/` folder and run:

```bash
terraform plan -out tfplan.binary
terraform show -json tfplan.binary > tfplan.json
```

Run OPA:

```bash
opa eval -f pretty -d ../policy.rego -i tfplan.json "data.terraform.aws.deny"
```

Expected result: `["One or more policy violations should be reported here"]`

Your exact output may differ depending on the snippets you selected, but the result should not be an empty list.

Important:

The policy.rego file is located in the root of lab2.

When running OPA from within the good/ or bad/ folders, you must reference the policy file using a relative path: "-d ../policy.rego"

If you do not specify the correct path, OPA will not be able to locate your policy.

Note: A proposed solution rego file is at `qa-opa-labs\solution` Only use this is absolutely necessary

### Final Takeaway

A Terraform plan can be technically valid and still be rejected.

OPA enforces organisational standards by evaluating infrastructure before deployment.






