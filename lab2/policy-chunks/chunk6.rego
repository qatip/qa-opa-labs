deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_instance"

  not rc.change.after.associate_public_ip_address

  msg := "Public IP required"
}