package terraform.ssh_test

import data.terraform.ssh
import rego.v1

# Fixtures model the standalone ingress rule observed in Michael's real plan.
base_rule := {
	"cidr_ipv4": "0.0.0.0/0",
	"cidr_ipv6": null,
	"ip_protocol": "tcp",
	"from_port": 22,
	"to_port": 22,
}

resource_for(rule) := {
	"address": "aws_vpc_security_group_ingress_rule.ssh",
	"mode": "managed",
	"type": "aws_vpc_security_group_ingress_rule",
	"change": {
		"actions": ["create"],
		"after": rule,
		"after_unknown": {"security_group_id": true},
	},
}

plan_for(rule) := {"resource_changes": [resource_for(rule)]}

test_public_ssh_denied_with_reason if {
	result := ssh.decision with input as plan_for(base_rule)
	result.allow == false
	result.deny == ["aws_vpc_security_group_ingress_rule.ssh: SSH must not be open to the internet"]
}

test_restricted_ipv4_allowed if {
	rule := object.union(base_rule, {"cidr_ipv4": "203.0.113.10/32"})
	ssh.allow with input as plan_for(rule)
}

test_public_ipv6_ssh_denied if {
	rule := object.union(base_rule, {"cidr_ipv4": null, "cidr_ipv6": "::/0"})
	not ssh.allow with input as plan_for(rule)
}

test_restricted_ipv6_allowed if {
	rule := object.union(base_rule, {"cidr_ipv4": null, "cidr_ipv6": "2001:db8::1/128"})
	ssh.allow with input as plan_for(rule)
}

test_range_including_ssh_denied if {
	rule := object.union(base_rule, {"from_port": 1, "to_port": 1024})
	not ssh.allow with input as plan_for(rule)
}

test_range_below_ssh_allowed if {
	rule := object.union(base_rule, {"from_port": 1, "to_port": 21})
	ssh.allow with input as plan_for(rule)
}

test_range_above_ssh_allowed if {
	rule := object.union(base_rule, {"from_port": 23, "to_port": 1024})
	ssh.allow with input as plan_for(rule)
}

test_all_protocols_denied if {
	rule := object.union(base_rule, {"ip_protocol": "-1", "from_port": null, "to_port": null})
	not ssh.allow with input as plan_for(rule)
}

test_numeric_all_protocols_denied if {
	rule := object.union(base_rule, {"ip_protocol": -1, "from_port": null, "to_port": null})
	not ssh.allow with input as plan_for(rule)
}

test_tcp_protocol_number_string_denied if {
	rule := object.union(base_rule, {"ip_protocol": "6"})
	not ssh.allow with input as plan_for(rule)
}

test_udp_22_allowed_by_this_ssh_policy if {
	rule := object.union(base_rule, {"ip_protocol": "udp"})
	ssh.allow with input as plan_for(rule)
}

test_unknown_source_denied if {
	resource := resource_for(object.union(base_rule, {"cidr_ipv4": null}))
	change := object.union(resource.change, {"after_unknown": {"cidr_ipv4": true}})
	plan := {"resource_changes": [object.union(resource, {"change": change})]}
	result := ssh.decision with input as plan
	result.allow == false
	count(result.deny) == 1
}

test_unknown_group_id_does_not_block if {
	rule := object.union(base_rule, {"cidr_ipv4": "203.0.113.10/32"})
	ssh.allow with input as plan_for(rule)
}

test_delete_insecure_rule_allowed if {
	resource := resource_for(base_rule)
	change := {"actions": ["delete"], "before": base_rule, "after": null, "after_unknown": {}}
	plan := {"resource_changes": [object.union(resource, {"change": change})]}
	ssh.allow with input as plan
}

test_unchanged_insecure_rule_denied if {
	resource := resource_for(base_rule)
	change := object.union(resource.change, {"actions": ["no-op"]})
	plan := {"resource_changes": [object.union(resource, {"change": change})]}
	not ssh.allow with input as plan
}

test_missing_plan_structure_denied if {
	not ssh.allow with input as {}
}

test_errored_plan_denied if {
	not ssh.allow with input as {"errored": true, "resource_changes": []}
}

test_empty_change_array_allowed if {
	ssh.allow with input as {"resource_changes": []}
}
