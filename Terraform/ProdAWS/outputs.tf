output "vpc_id" {
  value = aws_vpc.clickstream.id
}

output "public_subnet_ids" {
  value = [for az in local.azs : aws_subnet.public[az].id]
}

output "oltp_subnet_ids" {
  value = [for az in local.azs : aws_subnet.oltp[az].id]
}

output "analytics_subnet_ids" {
  value = [for az in local.azs : aws_subnet.analytics[az].id]
}

output "s3_buckets" {
  value = {
    media     = aws_s3_bucket.media.bucket
    raw       = aws_s3_bucket.raw.bucket
    processed = aws_s3_bucket.processed.bucket
  }
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cognito" {
  value = {
    user_pool_id = aws_cognito_user_pool.users.id
    client_id    = aws_cognito_user_pool_client.app.id
  }
}

output "api_invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "lambda_functions" {
  value = {
    ingest = aws_lambda_function.ingest.arn
    etl    = aws_lambda_function.etl.arn
  }
}

output "ec2_instances" {
  value = {
    oltp  = aws_instance.oltp.id
    dwh   = aws_instance.dwh.id
    shiny = aws_instance.shiny.id
  }
}

output "shiny_alb_dns" {
  value       = var.enable_shiny_alb ? aws_lb.shiny[0].dns_name : ""
  description = "DNS for the internal ALB fronting Shiny (blank when disabled)."
}

output "amplify_app_id" {
  value       = var.enable_amplify ? aws_amplify_app.frontend[0].id : ""
  description = "Amplify app ID when enabled."
}

output "s3_vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}
