terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  lambda_src_dir   = "${path.module}/../lambda"
  lambda_build_dir = "${path.module}/build"
}

# ---------------------------------------------------------------------------
# Lambda deployment package
# ---------------------------------------------------------------------------

resource "null_resource" "lambda_build" {
  triggers = {
    handler_hash      = filemd5("${local.lambda_src_dir}/handler.py")
    hotels_hash       = filemd5("${local.lambda_src_dir}/hotels.yaml")
    requirements_hash = filemd5("${local.lambda_src_dir}/requirements.txt")
    build_script_hash = filemd5("${path.module}/../scripts/build_lambda.sh")
  }

  provisioner "local-exec" {
    command = "bash '${path.module}/../scripts/build_lambda.sh' '${local.lambda_build_dir}' '${local.lambda_src_dir}'"
  }
}

data "archive_file" "lambda_zip" {
  depends_on  = [null_resource.lambda_build]
  type        = "zip"
  source_dir  = local.lambda_build_dir
  output_path = "${path.module}/lambda.zip"
}

# ---------------------------------------------------------------------------
# SES identity (sender)
#
# Terraform creates the identity and triggers a verification email to
# ses_from_email. The address must be clicked before SES will send from it.
#
# NOTE: SES starts in sandbox mode — the recipient (notification_email) must
# also be verified until you request production access in the AWS console.
# ---------------------------------------------------------------------------

resource "aws_ses_email_identity" "sender" {
  email = var.ses_from_email
}

# Recipient identities — required while SES account is in sandbox mode
resource "aws_ses_email_identity" "recipients" {
  for_each = toset(var.notification_emails)
  email    = each.value
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda_role" {
  name = "hotelscraper-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ses_send" {
  name = "hotelscraper-ses-send"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ses:SendEmail"
      Resource = "*"  # Must be * — SES checks both sender and recipient identities
    }]
  })
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "hotelscraper" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "hotelscraper"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 300 # 5 minutes — 5 nights × N hotels with API latency

  environment {
    variables = {
      SERPAPI_TOKEN      = var.serpapi_token
      SES_FROM_EMAIL     = var.ses_from_email
      NOTIFICATION_EMAIL = join(",", var.notification_emails)
    }
  }
}

# ---------------------------------------------------------------------------
# EventBridge scheduled rule
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "hotelscraper-daily"
  description         = "Triggers the hotel price scraper on a daily schedule"
  schedule_expression = var.schedule_expression # Wed+Thu 3 PM CST = cron(0 21 ? * WED,THU *)
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_schedule.name
  target_id = "hotelscraper-lambda"
  arn       = aws_lambda_function.hotelscraper.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hotelscraper.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
}
