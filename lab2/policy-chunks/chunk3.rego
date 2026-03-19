required_tags := {"Owner", "Environment", "ManagedBy"}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_instance"
  not is_delete(rc)

  tag := required_tags[_]
  not rc.change.after.tags[tag]

  msg := sprintf("Instance is missing required tag %q", [tag])
}
