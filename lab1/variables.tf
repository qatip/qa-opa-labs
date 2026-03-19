variable "aws_region" {
  type        = string
  description = "AWS region for the demo"
  default     = "eu-west-2"
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the bucket"
}