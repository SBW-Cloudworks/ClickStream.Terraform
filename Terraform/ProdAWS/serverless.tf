resource "aws_cloudwatch_log_group" "lambda_ingest" {
  name              = "/aws/lambda/ClickstreamIngest"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "lambda_etl" {
  name              = "/aws/lambda/ClickstreamETL"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "ingest" {
  function_name = "ClickstreamIngest"
  role          = aws_iam_role.lambda.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  filename         = var.lambda_ingest_zip
  source_code_hash = filebase64sha256(var.lambda_ingest_zip)

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  vpc_config {
    subnet_ids         = [for az in local.azs : aws_subnet.oltp[az].id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge({
      RAW_BUCKET = aws_s3_bucket.raw.bucket
      TOPIC_ARN  = aws_sns_topic.alerts.arn
    }, var.lambda_extra_environment)
  }
}

resource "aws_lambda_function" "etl" {
  function_name = "ClickstreamETL"
  role          = aws_iam_role.lambda.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  filename         = var.lambda_etl_zip
  source_code_hash = filebase64sha256(var.lambda_etl_zip)

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  vpc_config {
    subnet_ids         = [for az in local.azs : aws_subnet.analytics[az].id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge({
      RAW_BUCKET       = aws_s3_bucket.raw.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
    }, var.lambda_extra_environment)
  }
}
