deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_instance"
  not is_delete(rc)

  instance_type := rc.change.after.instance_type
  not instance_type == "t3.micro"
  not instance_type == "t3.small"

  msg := sprintf("Instance type %q is not approved", [instance_type])
}