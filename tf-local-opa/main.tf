resource "aws_s3_bucket" "demo" {
  bucket = var.bucket_name
  tags   = var.tags
}


resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
