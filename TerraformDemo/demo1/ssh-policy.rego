package terraform.ssh

import rego.v1

# Scope: standalone aws_vpc_security_group_ingress_rule resources in plan JSON.
# Inline aws_security_group rules and legacy aws_security_group_rule are not covered.
default allow := false

allow if {
	is_array(input.resource_changes)
	count(deny) == 0
}

decision := {"allow": allow, "deny": sort(deny)}

deny contains "Input must be Terraform plan JSON with a resource_changes array" if {
	not is_array(input.resource_changes)
}

deny contains "Terraform reported an errored plan" if {
	input.errored == true
}

# Inspect the proposed state, including unchanged rules. Ignore deleted rules.
ingress_rules contains resource if {
	some resource in input.resource_changes
	resource.type == "aws_vpc_security_group_ingress_rule"
	resource.change.after != null
}

internet_source(rule) if {
	rule.cidr_ipv4 == "0.0.0.0/0"
}

internet_source(rule) if {
	rule.cidr_ipv6 == "::/0"
}

permits_ssh(rule) if {
	rule.ip_protocol in {"tcp", "6", 6}
	rule.from_port <= 22
	rule.to_port >= 22
}

permits_ssh(rule) if {
	rule.ip_protocol in {"-1", -1}
}

deny contains msg if {
	some resource in ingress_rules
	rule := resource.change.after
	internet_source(rule)
	permits_ssh(rule)
	msg := sprintf("%s: SSH must not be open to the internet", [resource.address])
}

# Unknown group IDs are normal. Unknown policy-critical fields require review.
deny contains msg if {
	some resource in ingress_rules
	some field in {"cidr_ipv4", "cidr_ipv6", "ip_protocol", "from_port", "to_port"}
	resource.change.after_unknown[field] == true
	msg := sprintf("%s: %s is unknown at plan time; cannot approve", [resource.address, field])
}
