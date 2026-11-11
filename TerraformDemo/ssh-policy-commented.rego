# OPA / TERRAFORM SSH DEMO - COMMENTED POLICY
#
# Purpose: reject planned standalone ingress rules that expose TCP port 22
# to the entire IPv4 or IPv6 internet. Also reject unknown policy-critical
# values rather than guessing whether they will be safe after deployment.
#
# This is a commented alternative to ssh-policy.rego. Its executable Rego
# is unchanged. Load one policy copy at a time, especially when using -d .
#
# INPUT: the complete JSON produced by terraform show -json <saved-plan>.
# Do not supply only the individual ingress rule object. This file expects
# resource_changes at the root, rather than an HCP Terraform input wrapper.
#
# Example from PowerShell, with the commented files in the current folder:
#   opa eval --format=pretty --data .\ssh-policy-commented.rego `
#     --input .\ssh-before.json 'data.terraform.ssh.decision'
#
# OPA calculates a decision. A calling script or pipeline must inspect that
# decision and stop Terraform when it is denied. Merely displaying an OPA
# evaluation does not prevent someone from running terraform apply directly.
#
# READING REGO:
#   := defines a value or binds a local variable; == compares values.
#   Every expression inside one rule body must hold (logical AND).
#   Alternative bodies for the same boolean helper provide logical OR.
#   Rego describes conditions; this file is not an ordered instruction list.
#
# SCOPE: this is a focused course example, not full plan schema validation
# or a complete network security policy. It does not enforce a corporate
# CIDR allowlist or cover every way an AWS security group can be defined.
#
# References:
#   https://www.openpolicyagent.org/docs/policy-language
#   https://developer.hashicorp.com/terraform/internals/json-format

# The package places these rules under data.terraform.ssh. For example,
# the decision rule is queried as data.terraform.ssh.decision.

package terraform.ssh

# Use Rego v1 syntax, including if for rule bodies and contains for set
# membership rules. This also makes the syntax explicit in the file.

import rego.v1

# Scope: standalone aws_vpc_security_group_ingress_rule resources in plan JSON.
# Inline aws_security_group rules and legacy aws_security_group_rule are not covered.
# Give allow a defined Boolean false value when its positive rule does
# not match. Without a default, a nonmatching Boolean rule can be undefined;
# undefined is the absence of a value, not the JSON value null.

default allow := false

# Approve only if the expected top-level array exists AND no denial
# messages have been collected. An empty array is deliberately acceptable:
# this policy does not require a plan to contain an ingress rule.
# The default above applies whenever these conditions do not both hold.
allow if {
	is_array(input.resource_changes)
	count(deny) == 0
}

# Expose one object for the PowerShell gate to consume. deny is a set;
# sort converts it into a consistently ordered array for JSON output.
# The gate expects allow=true and an empty deny array before it applies.
decision := {"allow": allow, "deny": sort(deny)}

# Each matching deny rule contributes a message to the same set. Sets
# remove duplicates, and several different messages can accumulate.
# not is_array(...) also catches a missing resource_changes property:
# the positive check cannot succeed when the property is absent.
# This checks the array's presence/type, not the whole Terraform schema.

deny contains "Input must be Terraform plan JSON with a resource_changes array" if {
	not is_array(input.resource_changes)
}

# Reject an explicitly errored plan even if its resource_changes is an
# empty array. A missing errored property or errored=false does not match
# this rule; neither is the same as the explicit comparison to true.

deny contains "Terraform reported an errored plan" if {
	input.errored == true
}

# Inspect the proposed state, including unchanged rules. Ignore deleted rules.
# Build a set of the resource change objects relevant to this demo.
# some resource in ... considers array members, binding resource to each
# candidate. Only standalone ingress resources pass the type comparison.
# change.after contains the proposed resource values. A deleted resource
# has after=null and is excluded; a missing after also cannot satisfy the
# comparison. This rule does not inspect actions, so a no-op resource with
# an existing insecure after value is still checked.
# The resource address is retained so denial messages identify the rule.

ingress_rules contains resource if {
	some resource in input.resource_changes
	resource.type == "aws_vpc_security_group_ingress_rule"
	resource.change.after != null
}

# First way for internet_source(rule) to succeed: the IPv4 source is the
# canonical entire-internet CIDR. These are exact string comparisons,
# not subnet calculations. A non-/0 range is not thereby approved against
# an organisation's own permitted networks.

internet_source(rule) if {
	rule.cidr_ipv4 == "0.0.0.0/0"
}

# Second way for the same helper to succeed: the IPv6 source is ::/0.
# Either helper body is enough. This prevents an IPv4-only check from
# overlooking unrestricted IPv6 access.

internet_source(rule) if {
	rule.cidr_ipv6 == "::/0"
}

# TCP is identified by its name, protocol-number string, or numeric
# protocol number 6. The braces after in define a set of accepted values.
# Both inclusive port comparisons must hold. This catches exactly port 22
# and wider ranges such as 1-1024; checking only from_port==22 would miss
# those ranges. All comparisons in this body are required together.

permits_ssh(rule) if {
	rule.ip_protocol in {"tcp", "6", 6}
	rule.from_port <= 22
	rule.to_port >= 22
}

# AWS also represents all IP protocols with -1. Such a rule includes TCP
# SSH without needing explicit port bounds, so this alternative body does
# not compare from_port or to_port. Both string and numeric -1 are handled.

permits_ssh(rule) if {
	rule.ip_protocol in {"-1", -1}
}

# For every selected resource, name its proposed values rule, then ask
# both helper questions. A denial is added only when the source is the
# whole internet AND the rule permits SSH.
# sprintf substitutes the Terraform resource address into the message.
# The local name msg is the string contributed to the deny set.

deny contains msg if {
	some resource in ingress_rules
	rule := resource.change.after
	internet_source(rule)
	permits_ssh(rule)
	msg := sprintf("%s: SSH must not be open to the internet", [resource.address])
}

# Unknown group IDs are normal. Unknown policy-critical fields require review.
# Terraform can know a resource will exist while some values remain
# unknown until apply. after_unknown records that metadata separately
# from the proposed values in after. A null in after alone does not tell
# us whether a field is unknown or simply unused.
#
# Check each of these five field names using dynamic object lookup:
# after_unknown[field]. An explicit true adds a denial for that field.
# A missing or false flag does not match. Several unknown fields can add
# several messages. This conservative check runs for every selected ingress
# rule, even if its known fields did not trigger the public-SSH check.
#
# security_group_id is intentionally absent from the set. Its being unknown
# is normal when creating a group, and its value is not needed for this
# source/protocol/port check. The policy is not validating every unknown
# attribute, nor every missing or malformed attribute in arbitrary JSON.

deny contains msg if {
	some resource in ingress_rules
	some field in {"cidr_ipv4", "cidr_ipv6", "ip_protocol", "from_port", "to_port"}
	resource.change.after_unknown[field] == true
	msg := sprintf("%s: %s is unknown at plan time; cannot approve", [resource.address, field])
}
