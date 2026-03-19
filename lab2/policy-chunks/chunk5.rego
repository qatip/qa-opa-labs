deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_instance"
  not is_delete(rc)

  rc.change.after.associate_public_ip_address

  msg := "Instances must not have a public IP address"
}