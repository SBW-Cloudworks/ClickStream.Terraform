locals {
  common_tags = {
    Project = var.project_name
    Env     = "localstack"
    Region  = "ap-southeast-1"
  }
}

#############################
# S3 BUCKETS
# - Assets bucket (giả lập Amplify assets)
# - Raw clickstream bucket (RAW layer)
#############################

resource "aws_s3_bucket" "assets" {
  bucket = var.assets_bucket_name

  tags = merge(local.common_tags, {
    Purpose = "frontend-assets"
  })
}

resource "aws_s3_bucket" "raw_clickstream" {
  bucket = var.raw_clickstream_bucket_name

  tags = merge(local.common_tags, {
    Purpose = "clickstream-raw"
  })
}

#############################
# IAM ROLE CHO LAMBDA
#############################

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${var.project_name}-lambda-custom"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_clickstream.arn,
          "${aws_s3_bucket.raw_clickstream.arn}/*"
        ]
      }
    ]
  })
}

#############################
# LAMBDA FUNCTIONS
# - ingest: nhận event từ frontend qua API GW, ghi vào S3 raw
# - etl   : đọc từ S3 raw, transform (giả lập) – sau này lên AWS sẽ ghi vào PostgreSQL DW trên EC2
#############################

resource "aws_lambda_function" "ingest" {
  function_name = "${var.project_name}-ingest"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  filename      = var.lambda_ingest_zip_path
  timeout       = 10

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw_clickstream.bucket
    }
  }

  tags = merge(local.common_tags, { Function = "ingest" })
}

resource "aws_lambda_function" "etl" {
  function_name = "${var.project_name}-etl"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  filename      = var.lambda_etl_zip_path
  timeout       = 60

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw_clickstream.bucket
      # lên AWS thật sẽ thêm:
      # DW_HOST, DW_DB_NAME, DW_DB_USER, DW_DB_PASSWORD
    }
  }

  tags = merge(local.common_tags, { Function = "etl" })
}

#############################
# API GATEWAY HTTP API → LAMBDA INGEST
# Giả lập bước: Frontend → API Gateway (HTTP API) → Lambda Ingest
#############################

resource "aws_apigatewayv2_api" "clickstream" {
  name          = "${var.project_name}-http-api"
  protocol_type = "HTTP"

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "ingest_lambda" {
  api_id                 = aws_apigatewayv2_api.clickstream.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.ingest.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ingest_route" {
  api_id    = aws_apigatewayv2_api.clickstream.id
  route_key = "POST /clickstream"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.clickstream.id
  name        = "$default"
  auto_deploy = true

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_apigw_ingest" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
}

#############################
# EVENTBRIDGE (CLOUDWATCH EVENTS) → LAMBDA ETL
# Giả lập batch ETL pipeline
#############################

resource "aws_cloudwatch_event_rule" "etl_schedule" {
  name                = "${var.project_name}-etl-schedule"
  schedule_expression = var.etl_schedule_expression

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "etl_target" {
  rule      = aws_cloudwatch_event_rule.etl_schedule.name
  target_id = "etl-lambda"
  arn       = aws_lambda_function.etl.arn
}

resource "aws_lambda_permission" "allow_events_etl" {
  statement_id  = "AllowEventsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.etl_schedule.arn
}
