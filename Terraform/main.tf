terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

########################################
# PROVIDER LOCALSTACK
########################################

provider "aws" {
  region                      = "ap-southeast-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigateway       = "http://localhost:4566"
    cloudwatch       = "http://localhost:4566"
    cloudwatchevents = "http://localhost:4566"
    cloudwatchlogs   = "http://localhost:4566"
    cognitoidp       = "http://localhost:4566"
    ec2              = "http://localhost:4566"
    iam              = "http://localhost:4566"
    lambda           = "http://localhost:4566"
    s3               = "http://localhost:4566"
    sns              = "http://localhost:4566"
    sts              = "http://localhost:4566"
  }
}

########################################
# SNS TOPIC (FIXED)
########################################

resource "aws_sns_topic" "alerts" {
  name = "clickstream-local-alerts"
}

########################################
# COGNITO
########################################

resource "aws_cognito_user_pool" "user_pool" {
  name = "clickstream-user-pool"
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "clickstream-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

########################################
# S3 BUCKETS
########################################

resource "aws_s3_bucket" "media_bucket" {
  bucket = "local-media-assets"
}

resource "aws_s3_bucket" "raw_bucket" {
  bucket = "local-clickstream-raw"
}

resource "aws_s3_bucket" "processed_bucket" {
  bucket = "local-clickstream-processed"
}

########################################
# IAM ROLES
########################################

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-s3-logs"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:*"],
        Resource = ["*"]
      },
      {
        Effect = "Allow",
        Action = ["logs:*"],
        Resource = ["*"]
      },
      {
        Effect = "Allow",
        Action = ["sns:*"],
        Resource = ["*"]
      }
    ]
  })
}

########################################
# LAMBDA FUNCTIONS
########################################

resource "aws_lambda_function" "ingest" {
  function_name = "ClickstreamIngest"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"

  filename         = "${path.module}/lambda_ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_ingest.zip")

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw_bucket.bucket
      TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }
}

resource "aws_lambda_function" "etl" {
  function_name = "ClickstreamETL"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"

  filename         = "${path.module}/lambda_etl.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_etl.zip")

  environment {
    variables = {
      RAW_BUCKET       = aws_s3_bucket.raw_bucket.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed_bucket.bucket
    }
  }
}

########################################
# API GATEWAY (FIXED)
########################################

resource "aws_api_gateway_rest_api" "api" {
  name = "click-api"
}

resource "aws_api_gateway_resource" "click_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "click"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.click_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.click_resource.id
  http_method = aws_api_gateway_method.post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ingest.invoke_arn
}

resource "aws_lambda_permission" "api_permission" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_api_gateway_deployment" "api_deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on  = [
    aws_api_gateway_integration.integration
  ]
}

# FIXED: stage_name deprecated → create stage
resource "aws_api_gateway_stage" "api_stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deploy.id
  stage_name    = "prod"
}

########################################
# EVENTBRIDGE CRON → ETL LAMBDA
########################################

resource "aws_cloudwatch_event_rule" "etl_rule" {
  name                = "etl-hourly"
  schedule_expression = "cron(0 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "etl_target" {
  rule      = aws_cloudwatch_event_rule.etl_rule.name
  target_id = "etl-lambda"
  arn       = aws_lambda_function.etl.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl.function_name
  principal     = "events.amazonaws.com"
}

########################################
# OUTPUTS
########################################

output "api_invoke_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/${aws_api_gateway_stage.api_stage.stage_name}/_user_request_/click"
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "raw_bucket" {
  value = aws_s3_bucket.raw_bucket.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed_bucket.bucket
}
