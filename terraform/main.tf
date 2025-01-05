# Provider
provider "aws" {
  region = var.region
}

# SQS Queue
resource "aws_sqs_queue" "crypto_prices" {
  name = var.queue_name
}

# Lambda Function
resource "aws_lambda_function" "crypto_emitter" {
  filename         = "../build/emitter.zip"
  function_name    = "crypto-emitter"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "emitter.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.crypto_prices.id
      COIN_GECKO_KEY = "CG-Q9GWKQeAyt2V9ftCpE9kt1fB"
    }
  }

  layers = [
    aws_lambda_layer_version.requests_layer.arn
  ]

  source_code_hash = filebase64sha256("../build/emitter.zip")
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "crypto-emitter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Custom IAM Policy for Lambda to Access SQS
resource "aws_iam_policy" "lambda_sqs_policy" {
  name        = "lambda-sqs-access-policy"
  description = "Custom policy for Lambda to interact with SQS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Resource = aws_sqs_queue.crypto_prices.arn
      }
    ]
  })
}

# Attach Custom IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_custom_policy_attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_sqs_policy.arn
}

# Attach AWS-Managed Policy for Lambda SQS Execution
resource "aws_iam_role_policy_attachment" "lambda_sqs_managed_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# EventBridge Rule for Scheduling
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "crypto-emitter-schedule"
  schedule_expression = "rate(1 minute)"
}

# EventBridge Target for Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.lambda_schedule.name
  arn       = aws_lambda_function.crypto_emitter.arn
}

# Grant EventBridge Permission to Invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crypto_emitter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule.arn
}

# Lambda Layer
resource "aws_lambda_layer_version" "requests_layer" {
  filename         = "../build/python_modules.zip"
  layer_name       = "python-requests-layer"
  compatible_runtimes = ["python3.9"]
  source_code_hash = filebase64sha256("../build/python_modules.zip")
}
