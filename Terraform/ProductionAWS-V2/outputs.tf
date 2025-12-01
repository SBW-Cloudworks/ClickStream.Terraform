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
    media = aws_s3_bucket.media.bucket
    raw   = aws_s3_bucket.raw.bucket
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
    oltp      = aws_instance.oltp.id
    analytics = aws_instance.analytics.id
  }
}

output "shiny_alb_dns" {
  value       = aws_lb.shiny.dns_name
  description = "DNS for the internal ALB fronting Shiny."
}

output "privatelink" {
  value = {
    service_name   = aws_vpc_endpoint_service.privatelink.service_name
    endpoint_id    = aws_vpc_endpoint.privatelink_consumer.id
    endpoint_dns   = aws_vpc_endpoint.privatelink_consumer.dns_entry[0].dns_name
    nlb_dns        = aws_lb.privatelink.dns_name
  }
}

output "s3_vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}
