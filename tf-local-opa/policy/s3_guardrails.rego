package terraform.aws

required_tags := {"Environment", "Owner", "ManagedBy"}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket"
  not is_delete(rc)

  bucket_name := rc.change.after.bucket
  not startswith(bucket_name, "opa-demo-")

  msg := sprintf("S3 bucket %q must start with 'opa-demo-'", [bucket_name])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket"
  not is_delete(rc)

  tag := required_tags[_]
  not rc.change.after.tags[tag]

  msg := sprintf("S3 bucket %q is missing required tag %q", [rc.change.after.bucket, tag])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket"
  not is_delete(rc)

  not has_public_access_block

  msg := sprintf("S3 bucket %q must have an aws_s3_bucket_public_access_block resource", [rc.change.after.bucket])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)
  not rc.change.after.block_public_acls

  msg := "S3 public access block must set block_public_acls = true"
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)
  not rc.change.after.block_public_policy

  msg := "S3 public access block must set block_public_policy = true"
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)
  not rc.change.after.ignore_public_acls

  msg := "S3 public access block must set ignore_public_acls = true"
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)
  not rc.change.after.restrict_public_buckets

  msg := "S3 public access block must set restrict_public_buckets = true"
}

has_public_access_block if {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket_public_access_block"
  not is_delete(rc)
}

is_delete(rc) if {
  rc.change.actions[_] == "delete"
}