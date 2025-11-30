resource "aws_api_gateway_rest_api" "click_api" {
  name = var.api_name
}

resource "aws_api_gateway_resource" "click" {
  rest_api_id = aws_api_gateway_rest_api.click_api.id
  parent_id   = aws_api_gateway_rest_api.click_api.root_resource_id
  path_part   = "click"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.click_api.id
  resource_id   = aws_api_gateway_resource.click.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.click_api.id
  resource_id             = aws_api_gateway_resource.click.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ingest.invoke_arn
}

resource "aws_lambda_permission" "api_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.click_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "click" {
  rest_api_id = aws_api_gateway_rest_api.click_api.id

  depends_on = [
    aws_api_gateway_integration.lambda
  ]
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.click_api.id}/${var.api_stage}"
  retention_in_days = var.log_retention_days
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.click_api.id
  deployment_id = aws_api_gateway_deployment.click.id
  stage_name    = var.api_stage

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = "{ \"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"resourcePath\":\"$context.resourcePath\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\" }"
  }

  xray_tracing_enabled = true
}
