output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.hotelscraper.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.hotelscraper.arn
}

output "ses_identity_arn" {
  description = "ARN of the verified SES sender identity"
  value       = aws_ses_email_identity.sender.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule driving the schedule"
  value       = aws_cloudwatch_event_rule.daily_schedule.arn
}
