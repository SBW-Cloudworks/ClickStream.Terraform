resource "aws_cloudwatch_event_rule" "etl" {
  name                = "clickstream-etl-schedule"
  schedule_expression = var.etl_schedule_expression
}

resource "aws_cloudwatch_event_target" "etl" {
  rule      = aws_cloudwatch_event_rule.etl.name
  target_id = "etl-lambda"
  arn       = aws_lambda_function.etl.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.etl.arn
}
