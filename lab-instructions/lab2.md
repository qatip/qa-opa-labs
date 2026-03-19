## Lab 2 – Build an OPA Policy from Snippets

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

1. Review the governance requirements above
2. Review the Rego snippets in `policy-chunks/`
3. Identify which snippets enforce the required controls
4. Combine the correct snippets into a single file:

```text
policy.rego