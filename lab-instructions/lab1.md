# Lab 1 – Introduction to Policy Enforcement with OPA and Terraform

© 2026 QA Michael Coulling-Green

## Overview

In this lab, you will deploy a simple AWS resource using Terraform and introduce policy enforcement using Open Policy Agent (OPA).

Terraform is responsible for defining and provisioning infrastructure. However, it does not enforce organisational standards by default. OPA is used to evaluate Terraform plans and ensure they comply with defined rules before deployment.

---

## Learning Objectives

By the end of this lab, you will be able to:

- Understand the difference between infrastructure provisioning and policy enforcement
- Generate a Terraform execution plan and export it as JSON
- Use OPA to evaluate a Terraform plan against policy rules
- Identify and interpret policy violations
- Modify infrastructure code to meet governance requirements

---

## Scenario

You are working within an organisation that allows teams to deploy infrastructure using Terraform.

However, all resources must comply with defined standards for:

- Naming conventions
- Ownership and environment tagging
- Security configuration

To enforce these standards, OPA is used to evaluate Terraform plans before deployment.

---

## Key Concept

Terraform answers:

> Can this infrastructure be created?

OPA answers:

> Should this infrastructure be allowed?

---

## What You Will Build

In this lab, you will:

- Define an AWS S3 bucket using Terraform
- Generate a Terraform plan
- Evaluate the plan using OPA
- Introduce a policy violation
- Observe how OPA blocks non-compliant infrastructure

---

## Lab Steps

### Step 1. Configuring Access to AWS using Cloud9/Visual Studio Code 

If using Cloud9 as your IDE: 

Cloud9 uses temporary credentials by default which do not have sufficient authorization to complete some upcoming steps. Navigate to Preferences, AWS Settings, Credentials and disable temporary credentials before following the instructions regarding 'aws configure'

![12](../diagrams/12.png)
![9](../diagrams/9.png)

For All IDEs:

Open an IDE terminal session and use “aws configure” to supply explicit lab credentials, providing the Access Key and Secret Access Key generated for your student account. Leave Default region and Default output empty


![10](../diagrams/10.png)


### Step 2 – Review the Terraform Configuration

You are provided with a Terraform configuration at c:\qa-opa-labs\tf-local-opa that defines:

- An S3 bucket
- A public access block configuration
- A set of tags applied to the resource

At this stage, the configuration is valid and deployable.

---

### Step 3 – Generate a Terraform Plan

Run the following commands:

```bash
terraform init
terraform plan -out tfplan.binary