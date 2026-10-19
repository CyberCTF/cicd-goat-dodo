# Wonderland's "dodo" object store, as Terraform. Wonderland's CI deploys this module to AWS; a
# security scan (Checkov) runs first as a deploy gate and refuses a bucket that is publicly
# readable, so the bucket is created private. The bucket name and the access-control list are the
# only knobs a change would normally touch.
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# The dodo bucket. Wonderland keeps it PRIVATE: the pocket of curiosities the Dodo guards is not for
# the whole internet. CI's security scan enforces exactly this before a deploy is allowed.
resource "aws_s3_bucket" "dodo" {
  bucket = var.bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Project = "wonderland-dodo"
    Owner   = "caucus-race"
  }
}
