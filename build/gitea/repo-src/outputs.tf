output "bucket_id" {
  value       = aws_s3_bucket.dodo.id
  description = "Name (ID) of the dodo bucket."
}

output "bucket_arn" {
  value       = aws_s3_bucket.dodo.arn
  description = "ARN of the dodo bucket."
}
