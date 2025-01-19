# Provider
provider "aws" {
  region = var.region
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
      COIN_GECKO_KEY = var.coin_gecko_key
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

resource "aws_timestreamwrite_database" "crypto_timestream_db" {
  database_name = "crypto_timestream_db"

  tags = {
    Environment = "Production"
    Project     = "CryptoAnalytics"
  }
}

resource "aws_timestreamwrite_table" "crypto_prices" {
  database_name = aws_timestreamwrite_database.crypto_timestream_db.database_name
  table_name    = "crypto_prices"

  retention_properties {
    memory_store_retention_period_in_hours = 24  # Retain data in-memory for 24 hours
    magnetic_store_retention_period_in_days = 30 # Retain data on disk for 30 days
  }

  tags = {
    Environment = "Production"
    Project     = "CryptoAnalytics"
  }
}

resource "aws_iam_policy" "timestream_policy" {
    name        = "TimestreamAccessPolicy"
    description = "Policy for accessing Timestream from Lambda"
    policy      = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "timestream:WriteRecords",
                    "timestream:DescribeEndpoints"
                ]
                Resource = "*"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "lambda_timestream_policy" {
    role       = aws_iam_role.lambda_exec.name
    policy_arn = aws_iam_policy.timestream_policy.arn
}
