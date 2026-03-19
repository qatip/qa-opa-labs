package terraform.aws

required_tags := {"Owner", "Environment", "ManagedBy"}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_instance"
  not is_delete(rc)

  instance_type := rc.change.after.instance_type
  not instance_type == "t3.micro"
  not instance_type == "t3.small"

  msg := sprintf("Instance type %q is not approved", [instance_type])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_instance"
  not is_delete(rc)

  tag := required_tags[_]
  not rc.change.after.tags[tag]

  msg := sprintf("Instance is missing required tag %q", [tag])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_instance"
  not is_delete(rc)

  rc.change.after.associate_public_ip_address

  msg := "Instances must not have a public IP address"
}

is_delete(rc) if {
  rc.change.actions[_] == "delete"
}