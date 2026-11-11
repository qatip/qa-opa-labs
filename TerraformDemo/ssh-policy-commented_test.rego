# OPA / TERRAFORM SSH DEMO - COMMENTED UNIT TESTS
#
# These 18 tests evaluate the policy against small in-memory plan fixtures.
# They do not invoke Terraform, call AWS, or create/delete real resources.
# The executable Rego is unchanged from ssh-policy_test.rego.
#
# Run only the commented pair from PowerShell:
#   opa test .\ssh-policy-commented.rego .\ssh-policy-commented_test.rego -v
#
# Use these as alternatives to the original pair. Avoid loading both policy
# versions and both test versions together through a directory-wide command.
#
# HOW TO READ A TEST:
#   A test_ rule passes when its whole body succeeds. Every expression in
#   the body is an assertion that must hold, not a printed status message.
#   with input as ... temporarily supplies input for that expression; it
#   does not edit a JSON file, change AWS, or mutate another test's input.
#   ssh.allow succeeds when the policy returns true. not ssh.allow asserts
#   it does not succeed; here the policy's default makes denied allow=false.
#   := binds an immutable local value. == checks an expected value.
#
# The fixtures omit fields irrelevant to this policy. These are unit tests
# of its decisions, not provider validation tests or exhaustive coverage
# of all possible Terraform plan/resource shapes.
#
# References:
#   https://www.openpolicyagent.org/docs/policy-testing
#   https://www.openpolicyagent.org/docs/policy-reference/builtins/object

# Keep fixtures and tests in a separate package from the policy itself.
# OPA discovers the rules with test_ names when running opa test.
package terraform.ssh_test

# Import the policy package; ssh becomes the short reference used below,
# so ssh.decision means data.terraform.ssh.decision.
import data.terraform.ssh
import rego.v1

# Fixtures model the standalone ingress rule observed in Michael's real plan.
# The shared starting fixture permits TCP port 22 from all IPv4 sources.
# IPv6 is explicitly null because this rule uses an IPv4 source instead.
# It contains the relevant change.after fields from our real demo plan.
base_rule := {
	"cidr_ipv4": "0.0.0.0/0",
	"cidr_ipv6": null,
	"ip_protocol": "tcp",
	"from_port": 22,
	"to_port": 22,
}

# A helper function wraps any supplied ingress values in a resource-change
# object. address appears in denial text, while type selects policy scope.
# actions describes creation; after holds the proposed rule. The unknown
# security_group_id models a group whose ID will be assigned at apply.
# That unknown ID is intentionally present in the normal fixtures, so it
# must not prevent otherwise acceptable rules from passing.
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

# A second helper adds the root resource_changes array. This is the
# minimum plan envelope needed by the policy, with exactly one resource.
plan_for(rule) := {"resource_changes": [resource_for(rule)]}

# TEST 1 - Unrestricted IPv4 SSH must fail, with a useful explanation.
# Query the full decision using the unsafe base fixture. Check both the
# Boolean and the exact one-element message array, including its address.
test_public_ssh_denied_with_reason if {
	result := ssh.decision with input as plan_for(base_rule)
	result.allow == false
	result.deny == ["aws_vpc_security_group_ingress_rule.ssh: SSH must not be open to the internet"]
}

# TEST 2 - Restrict IPv4 SSH to one source address.
# object.union creates a new object; base_rule remains unchanged. Values
# on the right win conflicts, and nested objects are merged recursively.
# Here only the scalar cidr_ipv4 is overridden. 203.0.113.10/32 is a
# documentation example, not an instruction to permit a real user's IP.
# Passing means it satisfies this focused check, not every security policy.
test_restricted_ipv4_allowed if {
	rule := object.union(base_rule, {"cidr_ipv4": "203.0.113.10/32"})
	ssh.allow with input as plan_for(rule)
}

# TEST 3 - Unrestricted IPv6 SSH must fail too.
# Disable the IPv4 source and set IPv6 to ::/0, isolating the IPv6 case.
# The negated allow assertion expects the policy to deny the plan.
test_public_ipv6_ssh_denied if {
	rule := object.union(base_rule, {"cidr_ipv4": null, "cidr_ipv6": "::/0"})
	not ssh.allow with input as plan_for(rule)
}

# TEST 4 - A single IPv6 source passes this check.
# 2001:db8::1/128 is a documentation address. Keep IPv4 null so a leftover
# public IPv4 source does not obscure the IPv6 behaviour being tested.
test_restricted_ipv6_allowed if {
	rule := object.union(base_rule, {"cidr_ipv4": null, "cidr_ipv6": "2001:db8::1/128"})
	ssh.allow with input as plan_for(rule)
}

# TEST 5 - A broad TCP port range that contains 22 must fail.
# The source remains public. Bounds 1 and 1024 exercise both comparisons
# and demonstrate why checking only a rule starting at 22 is insufficient.
test_range_including_ssh_denied if {
	rule := object.union(base_rule, {"from_port": 1, "to_port": 1024})
	not ssh.allow with input as plan_for(rule)
}

# TEST 6 - A public TCP range ending at 21 excludes SSH.
# This verifies the lower side of the port-22 boundary. It is accepted by
# this SSH-specific policy; the test does not declare those other ports safe.
test_range_below_ssh_allowed if {
	rule := object.union(base_rule, {"from_port": 1, "to_port": 21})
	ssh.allow with input as plan_for(rule)
}

# TEST 7 - A public TCP range starting at 23 also excludes SSH.
# Together with tests 5 and 6, this checks ranges around port 22.
test_range_above_ssh_allowed if {
	rule := object.union(base_rule, {"from_port": 23, "to_port": 1024})
	ssh.allow with input as plan_for(rule)
}

# TEST 8 - String -1 means all IP protocols, so public access must fail.
# Ports are null to show that the all-protocols helper works without port
# bounds; TCP SSH is included even without an explicit TCP/22 pair.
test_all_protocols_denied if {
	rule := object.union(base_rule, {"ip_protocol": "-1", "from_port": null, "to_port": null})
	not ssh.allow with input as plan_for(rule)
}

# TEST 9 - Exercise the same all-protocols case with numeric -1.
# JSON numbers and strings are distinct, and the policy accepts either
# representation when identifying an all-protocols rule.
test_numeric_all_protocols_denied if {
	rule := object.union(base_rule, {"ip_protocol": -1, "from_port": null, "to_port": null})
	not ssh.allow with input as plan_for(rule)
}

# TEST 10 - TCP can appear as the protocol-number string "6".
# The other values still describe public port 22. This tests the string
# number variant; numeric 6 is also supported by the policy but does not
# have a separate test in this unchanged suite.
test_tcp_protocol_number_string_denied if {
	rule := object.union(base_rule, {"ip_protocol": "6"})
	not ssh.allow with input as plan_for(rule)
}

# TEST 11 - UDP port 22 does not match this TCP SSH restriction.
# This guards against blocking everything merely because its port is 22.
# Other policies could still reject this public UDP ingress rule.
test_udp_22_allowed_by_this_ssh_policy if {
	rule := object.union(base_rule, {"ip_protocol": "udp"})
	ssh.allow with input as plan_for(rule)
}

# TEST 12 - Refuse approval when the source CIDR is not yet known.
# Start with cidr_ipv4=null in after. Add cidr_ipv4=true in after_unknown
# to distinguish an unknown value from a deliberately absent source.
# The intermediate change and plan variables make each wrapping step clear.
# object.union recursively retains the existing security_group_id unknown
# flag while adding the CIDR flag. That ID alone must not cause a denial.
# Query the full decision and assert false plus exactly one denial. This
# test checks the number of reasons, not the unknown-field message wording;
# it exercises one of the five critical unknown fields, not all five.
test_unknown_source_denied if {
	resource := resource_for(object.union(base_rule, {"cidr_ipv4": null}))
	change := object.union(resource.change, {"after_unknown": {"cidr_ipv4": true}})
	plan := {"resource_changes": [object.union(resource, {"change": change})]}
	result := ssh.decision with input as plan
	result.allow == false
	count(result.deny) == 1
}

# TEST 13 - An unknown security-group ID is normal during group creation.
# Use the restricted IPv4 source and the fixture's unknown ID metadata.
# This intentionally has the same input as test 2, but makes the unknown-ID
# expectation explicit for the reader and for future policy changes.
test_unknown_group_id_does_not_block if {
	rule := object.union(base_rule, {"cidr_ipv4": "203.0.113.10/32"})
	ssh.allow with input as plan_for(rule)
}

# TEST 14 - Allow removal of an existing insecure rule.
# before shows the insecure old values; after=null means it will not exist
# after apply. The policy filters on after, rather than rejecting a resource
# just because its historical values were insecure. actions records delete.
# The recursive union retains other fixture keys; after is overridden with
# null, which is the value that makes this resource leave policy scope.
test_delete_insecure_rule_allowed if {
	resource := resource_for(base_rule)
	change := {"actions": ["delete"], "before": base_rule, "after": null, "after_unknown": {}}
	plan := {"resource_changes": [object.union(resource, {"change": change})]}
	ssh.allow with input as plan
}

# TEST 15 - An unchanged insecure rule must still fail review.
# Change actions to no-op while keeping the public SSH after values. The
# policy checks the proposed state, rather than filtering only creates or
# updates. An unrelated plan does not excuse a known insecure rule that is
# present in its resource_changes array.
test_unchanged_insecure_rule_denied if {
	resource := resource_for(base_rule)
	change := object.union(resource.change, {"actions": ["no-op"]})
	plan := {"resource_changes": [object.union(resource, {"change": change})]}
	not ssh.allow with input as plan
}

# TEST 16 - Empty JSON is not an acceptable Terraform plan input.
# With no resource_changes array, the positive allow rule cannot succeed.
# The policy also supplies an input-shape denial reason, although this test
# asserts only that allow does not succeed.
test_missing_plan_structure_denied if {
	not ssh.allow with input as {}
}

# TEST 17 - An explicit Terraform planning error must prevent approval.
# Even though resource_changes is a valid empty array, errored=true adds
# a denial. This distinguishes a failed plan from a successful empty plan.
test_errored_plan_denied if {
	not ssh.allow with input as {"errored": true, "resource_changes": []}
}

# TEST 18 - A well-shaped empty plan passes this focused check.
# There is nothing relevant to deny, and no error flag. This deliberately
# differs from test 16: an empty array exists here; the property is not
# missing. Passing does not prove the input is a fully validated plan.
test_empty_change_array_allowed if {
	ssh.allow with input as {"resource_changes": []}
}
