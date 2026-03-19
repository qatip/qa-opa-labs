# Lab 1 – Introduction to Policy Enforcement with OPA and Terraform

© 2026 QA Michael Coulling-Green

# Lab Overview

In this lab, you will deploy a simple AWS resource using Terraform and introduce policy enforcement using Open Policy Agent (OPA).

You will see that while Terraform is responsible for defining and provisioning infrastructure, it does not enforce organisational standards by default. OPA is used to evaluate Terraform plans and ensure they comply with defined rules before deployment.

# Learning Objectives

By the end of this lab, you will be able to:

Understand the difference between infrastructure provisioning and policy enforcement
Generate a Terraform execution plan and export it as JSON
Use OPA to evaluate a Terraform plan against policy rules
Identify and interpret policy violations
Modify infrastructure code to meet governance requirements
Ensure you have cloned the class repo onto your IDE machine into c:\qa-opa-labs.
Instructions assume the repo is at c:\qa-opa-labs, adjust all paths as necessary 

