variable "region" {
  type        = string
  description = "AWS region the dodo bucket is deployed to."
  default     = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Name of the dodo object-store bucket."
  default     = "dodo"
}
