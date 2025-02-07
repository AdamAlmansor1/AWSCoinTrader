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
      coin_gecko_key = var.coin_gecko_key
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

# IAM Policy for Logging
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging_policy"
  description = "Allows Lambda to write logs to CloudWatch"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach Logging Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_logging_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

# EventBridge Rule for Scheduling
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "crypto-emitter-schedule"
  schedule_expression = "rate(5 minutes)"
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
                Effect = "Allow",
                Action = [
                    "timestream:WriteRecords",
                    "timestream:DescribeEndpoints",
                    "timestream:Select"
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

# SMA Table
resource "aws_timestreamwrite_table" "sma_indicators" {
  database_name = aws_timestreamwrite_database.crypto_timestream_db.database_name
  table_name    = "sma_indicators"
  
  retention_properties {
    memory_store_retention_period_in_hours = 24    # 1 day in memory
    magnetic_store_retention_period_in_days = 7    # 7 days on disk
  }
}

# Lambda Function
resource "aws_lambda_function" "sma_calculator" {
  filename         = "../build/sma_calculator.zip"
  function_name    = "sma-calculator"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "sma_calculator.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300  # 5 minutes
  memory_size      = 512

  environment {
    variables = {
      TIMESTREAM_DB    = "crypto_db"
      RAW_TABLE        = "prices"
      PROCESSED_TABLE  = "sma_indicators"
    }
  }

  layers = [
    aws_lambda_layer_version.requests_layer.arn
  ]

  source_code_hash = filebase64sha256("../build/sma_calculator.zip")
}

# Run every 5 minutes
resource "aws_cloudwatch_event_rule" "sma_schedule" {
  name                = "sma-calculation-schedule"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "sma_target" {
  rule      = aws_cloudwatch_event_rule.sma_schedule.name
  arn       = aws_lambda_function.sma_calculator.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sma_calculator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sma_schedule.arn
}

# IAM Policy for Timestream Access (Query + Write)
resource "aws_iam_policy" "timestream_full_access" {
  name        = "TimestreamFullAccessPolicy"
  description = "Allows Lambda to query and write to Timestream"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "timestream:Query",
          "timestream:WriteRecords",
          "timestream:DescribeEndpoints"
        ],
        Resource = "*"
      }
    ]
  })
}

# Attach Timestream Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_timestream_full_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.timestream_full_access.arn
}