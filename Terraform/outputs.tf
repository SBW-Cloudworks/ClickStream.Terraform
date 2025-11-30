output "api_endpoint" {
  description = "Base URL for HTTP API Gateway in LocalStack"
  value       = aws_apigatewayv2_api.clickstream.api_endpoint
}

output "raw_bucket" {
  description = "S3 bucket name for raw clickstream events"
  value       = aws_s3_bucket.raw_clickstream.bucket
}

output "assets_bucket" {
  description = "S3 bucket name for frontend assets (Amplify simulated)"
  value       = aws_s3_bucket.assets.bucket
}
