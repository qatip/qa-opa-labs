deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket"
  not is_delete(rc)

  msg := "Invalid resource"
}