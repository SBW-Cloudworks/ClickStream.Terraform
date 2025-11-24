terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.63"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
  }
}

variable "project" {
  description = "Project name prefix for resource naming."
  type        = string
  default     = "clickstream"
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "local"
}

variable "region" {
  description = "AWS region for LocalStack emulation."
  type        = string
  default     = "ap-southeast-1"
}

variable "enable_ec2" {
  description = "Create EC2 placeholders (enable only if LocalStack EC2 is configured)."
  type        = bool
  default     = false
}

variable "ec2_ami" {
  description = "AMI ID for placeholder EC2 instances (ignored when enable_ec2 is false)."
  type        = string
  default     = "ami-12345678"
}

variable "localstack_endpoint" {
  description = "Base edge endpoint for LocalStack."
  type        = string
  default     = "http://localhost:4566"
}

locals {
  prefix = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigateway       = var.localstack_endpoint
    cloudwatch       = var.localstack_endpoint
    cloudwatchevents = var.localstack_endpoint
    cloudwatchlogs   = var.localstack_endpoint
    cognitoidp       = var.localstack_endpoint
    ec2              = var.localstack_endpoint
    iam              = var.localstack_endpoint
    lambda           = var.localstack_endpoint
    s3               = var.localstack_endpoint
    sns              = var.localstack_endpoint
    sts              = var.localstack_endpoint
  }
}

# -----------------------
# Networking (VPC, Subnets, Routes, Endpoint)
# -----------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${local.prefix}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.prefix}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "${local.prefix}-public" })
}

resource "aws_subnet" "private_oltp" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"
  tags              = merge(local.tags, { Name = "${local.prefix}-oltp" })
}

resource "aws_subnet" "private_analytics" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.region}a"
  tags              = merge(local.tags, { Name = "${local.prefix}-analytics" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags, { Name = "${local.prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.prefix}-private-rt" })
}

resource "aws_route_table_association" "oltp" {
  subnet_id      = aws_subnet.private_oltp.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "analytics" {
  subnet_id      = aws_subnet.private_analytics.id
  route_table_id = aws_route_table.private.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = merge(local.tags, { Name = "${local.prefix}-s3-endpoint" })
}

# -----------------------
# Security Groups
# -----------------------
resource "aws_security_group" "lambda" {
  name        = "${local.prefix}-lambda-sg"
  description = "Lambda ENI access inside the VPC"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.prefix}-lambda-sg" })
}

resource "aws_security_group" "oltp" {
  name        = "${local.prefix}-oltp-sg"
  description = "OLTP DB private ingress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "DB from Lambda"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.prefix}-oltp-sg" })
}

resource "aws_security_group" "analytics" {
  name        = "${local.prefix}-analytics-sg"
  description = "Analytics / Shiny ingress from Lambda"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Warehouse access"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  ingress {
    description     = "R Shiny"
    from_port       = 3838
    to_port         = 3838
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.prefix}-analytics-sg" })
}

# -----------------------
# Storage
# -----------------------
resource "aws_s3_bucket" "assets" {
  bucket        = "${local.prefix}-assets"
  force_destroy = true
  tags          = merge(local.tags, { Name = "${local.prefix}-assets" })
}

resource "aws_s3_bucket" "raw" {
  bucket        = "${local.prefix}-raw"
  force_destroy = true
  tags          = merge(local.tags, { Name = "${local.prefix}-raw" })
}

resource "aws_s3_bucket" "processed" {
  bucket        = "${local.prefix}-processed"
  force_destroy = true
  tags          = merge(local.tags, { Name = "${local.prefix}-processed" })
}

# -----------------------
# IAM for Lambda
# -----------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "Logs"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

  statement {
    sid = "S3"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.raw.arn,
      "${aws_s3_bucket.raw.arn}/*",
      aws_s3_bucket.processed.arn,
      "${aws_s3_bucket.processed.arn}/*"
    ]
  }

  statement {
    sid = "VpcNetworking"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = merge(local.tags, { Name = "${local.prefix}-lambda-role" })
}

resource "aws_iam_role_policy" "lambda_inline" {
  name   = "${local.prefix}-lambda-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# -----------------------
# Lambda source bundles
# -----------------------
data "archive_file" "ingest_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_ingest.zip"

  source {
    filename = "lambda_function.py"
    content  = <<-PYCODE
      import json
      import os
      import uuid
      import boto3


      def _client(service: str):
          host = os.environ.get("LOCALSTACK_HOSTNAME") or os.environ.get("LOCALSTACK_HOST") or "localhost"
          return boto3.client(service, endpoint_url=f"http://{host}:4566")


      def handler(event, context):
          body = event.get("body") if isinstance(event, dict) else None
          if not body:
              body = json.dumps({"message": "empty payload"})

          s3 = _client("s3")
          raw_bucket = os.environ["RAW_BUCKET"]
          key = f"ingest/{uuid.uuid4()}.json"
          s3.put_object(Bucket=raw_bucket, Key=key, Body=body.encode("utf-8"))

          return {
              "statusCode": 200,
              "body": json.dumps({"stored": key, "bucket": raw_bucket})
          }
    PYCODE
  }
}

data "archive_file" "etl_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_etl.zip"

  source {
    filename = "lambda_function.py"
    content  = <<-PYCODE
      import datetime as dt
      import json
      import os
      import boto3


      def _client(service: str):
          host = os.environ.get("LOCALSTACK_HOSTNAME") or os.environ.get("LOCALSTACK_HOST") or "localhost"
          return boto3.client(service, endpoint_url=f"http://{host}:4566")


      def handler(event, context):
          s3 = _client("s3")
          raw_bucket = os.environ["RAW_BUCKET"]
          processed_bucket = os.environ["PROCESSED_BUCKET"]

          resp = s3.list_objects_v2(Bucket=raw_bucket, Prefix="ingest/")
          objects = resp.get("Contents", [])

          summary = []
          for obj in objects:
              summary.append({"key": obj["Key"], "size": obj.get("Size", 0)})

          key = f"processed/{dt.datetime.utcnow().isoformat()}Z.json"
          s3.put_object(
              Bucket=processed_bucket,
              Key=key,
              Body=json.dumps({"count": len(summary), "objects": summary})
          )

          return {
              "statusCode": 200,
              "body": json.dumps({"processed": len(summary), "output": key})
          }
    PYCODE
  }
}

# -----------------------
# Lambda Functions
# -----------------------
resource "aws_lambda_function" "ingest" {
  function_name = "${local.prefix}-ingest"
  filename      = data.archive_file.ingest_zip.output_path
  source_code_hash = data.archive_file.ingest_zip.output_base64sha256
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 10
  memory_size      = 256

  vpc_config {
    subnet_ids         = [aws_subnet.private_oltp.id, aws_subnet.private_analytics.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw.bucket
    }
  }

  tags = merge(local.tags, { Name = "${local.prefix}-ingest" })
}

resource "aws_lambda_function" "etl" {
  function_name = "${local.prefix}-etl"
  filename      = data.archive_file.etl_zip.output_path
  source_code_hash = data.archive_file.etl_zip.output_base64sha256
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 30
  memory_size      = 512

  vpc_config {
    subnet_ids         = [aws_subnet.private_oltp.id, aws_subnet.private_analytics.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      RAW_BUCKET       = aws_s3_bucket.raw.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
    }
  }

  tags = merge(local.tags, { Name = "${local.prefix}-etl" })
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 7
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "etl" {
  name              = "/aws/lambda/${aws_lambda_function.etl.function_name}"
  retention_in_days = 7
  tags              = local.tags
}

# -----------------------
# API Gateway (ingestion)
# -----------------------
resource "aws_api_gateway_rest_api" "ingest" {
  name        = "${local.prefix}-api"
  description = "ClickStream ingest API"
  tags        = local.tags
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.ingest.id
  parent_id   = aws_api_gateway_rest_api.ingest.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "post_events" {
  rest_api_id   = aws_api_gateway_rest_api.ingest.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_events" {
  rest_api_id = aws_api_gateway_rest_api.ingest.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.ingest.arn}/invocations"
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ingest.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "ingest" {
  rest_api_id = aws_api_gateway_rest_api.ingest.id

  triggers = {
    redeploy = sha1(join("", [
      aws_api_gateway_integration.post_events.id,
      aws_lambda_function.ingest.source_code_hash
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.post_events,
    aws_lambda_permission.allow_apigw
  ]
}

resource "aws_api_gateway_stage" "ingest" {
  stage_name    = var.environment
  rest_api_id   = aws_api_gateway_rest_api.ingest.id
  deployment_id = aws_api_gateway_deployment.ingest.id
  tags          = local.tags
}

# -----------------------
# EventBridge (ETL schedule)
# -----------------------
resource "aws_cloudwatch_event_rule" "etl_hourly" {
  name                = "${local.prefix}-etl-hourly"
  description         = "Hourly ETL trigger"
  schedule_expression = "rate(1 hour)"
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "etl" {
  rule      = aws_cloudwatch_event_rule.etl_hourly.name
  target_id = "etl-lambda"
  arn       = aws_lambda_function.etl.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.etl_hourly.arn
}

# -----------------------
# Cognito (auth skeleton)
# -----------------------
resource "aws_cognito_user_pool" "users" {
  name = "${local.prefix}-users"
  tags = local.tags
}

resource "aws_cognito_user_pool_client" "frontend" {
  name         = "${local.prefix}-frontend"
  user_pool_id = aws_cognito_user_pool.users.id

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  generate_secret               = false
}

# -----------------------
# Monitoring / Alerts placeholder
# -----------------------
resource "aws_sns_topic" "alerts" {
  name = "${local.prefix}-alerts"
  tags = local.tags
}

# -----------------------
# Compute placeholders (EC2)
# -----------------------
resource "aws_instance" "oltp" {
  count                       = var.enable_ec2 ? 1 : 0
  ami                         = var.ec2_ami
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_oltp.id
  vpc_security_group_ids      = [aws_security_group.oltp.id]
  associate_public_ip_address = false

  tags = merge(local.tags, { Name = "${local.prefix}-oltp" })
}

resource "aws_instance" "analytics_dw" {
  count                       = var.enable_ec2 ? 1 : 0
  ami                         = var.ec2_ami
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_analytics.id
  vpc_security_group_ids      = [aws_security_group.analytics.id]
  associate_public_ip_address = false

  tags = merge(local.tags, { Name = "${local.prefix}-dw" })
}

resource "aws_instance" "r_shiny" {
  count                       = var.enable_ec2 ? 1 : 0
  ami                         = var.ec2_ami
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_analytics.id
  vpc_security_group_ids      = [aws_security_group.analytics.id]
  associate_public_ip_address = false

  tags = merge(local.tags, { Name = "${local.prefix}-rshiny" })
}

# -----------------------
# Outputs
# -----------------------
output "api_gateway_url" {
  description = "Invoke URL for ingest endpoint"
  value       = "${var.localstack_endpoint}/restapis/${aws_api_gateway_rest_api.ingest.id}/${var.environment}/_user_request_/events"
}

output "raw_bucket" {
  value       = aws_s3_bucket.raw.bucket
  description = "Raw clickstream bucket"
}

output "processed_bucket" {
  value       = aws_s3_bucket.processed.bucket
  description = "Processed clickstream bucket"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.users.id
  description = "Cognito user pool for frontend auth"
}
