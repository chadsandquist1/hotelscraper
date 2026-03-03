variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "ses_from_email" {
  description = "Email address SES sends from. Terraform will trigger a verification email to this address — it must be confirmed before SES will send."
  type        = string
}

variable "notification_emails" {
  description = "List of email addresses that receive hotel price alerts. In SES sandbox mode all addresses must be verified in SES."
  type        = list(string)
}

variable "serpapi_token" {
  description = "SerpAPI token used by the Lambda to call the Google Hotels API"
  type        = string
  sensitive   = true
}

variable "schedule_expression" {
  description = "EventBridge schedule expression controlling when the Lambda runs"
  type        = string
  default     = "cron(0 13 * * ? *)" # Daily at 8 AM EST (1 PM UTC)
}
