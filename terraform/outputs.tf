output "website_url" {
  description = "Public HTTP URL for the dashboard."
  value       = "http://${aws_lb.app.dns_name}"
}

output "load_balancer_dns" {
  value = aws_lb.app.dns_name
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.app.name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.visits.name
}

output "counter_lambda_name" {
  value = aws_lambda_function.counter.function_name
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifact.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}
