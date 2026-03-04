//new
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"

  backend "s3" {
    bucket         = "stocks-pipeline-tfstate-304161164217"
    key            = "stocks-pipeline/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "stocks-pipeline-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Variables ──────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "massive_api_key" {
  description = "Massive API key — pass via TF_VAR_massive_api_key env var, never hardcode"
  type        = string
  sensitive   = true
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for storing daily winners"
  type        = string
  default     = "stock-winners"
}

variable "event_bridge_lambda_zip_path" {
  description = "Zip for the EventBridge ingestion Lambda"
  type        = string
  default     = "event_bridge_lambda.zip"
}

variable "api_gateway_lambda_zip_path" {
  description = "Zip for the API Gateway Lambda"
  type        = string
  default     = "api_gateway_lambda.zip"
}

# ── DynamoDB Table ─────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "stock_winners" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Project = "stocks-pipeline"
  }
}

# ── IAM Roles ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "api_lambda_role" {
  name = "stocks-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "eb_lambda_role" {
  name = "stocks-eb-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_lambda_basic_execution" {
  role       = aws_iam_role.api_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "eb_lambda_basic_execution" {
  role       = aws_iam_role.eb_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_lambda_dynamo" {
  name = "stocks-api-lambda-dynamodb-policy"
  role = aws_iam_role.api_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:Query"]
      Resource = aws_dynamodb_table.stock_winners.arn
    }]
  })
}

resource "aws_iam_role_policy" "eb_lambda_dynamo" {
  name = "stocks-eb-lambda-dynamodb-policy"
  role = aws_iam_role.eb_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:Query", "dynamodb:PutItem"]
      Resource = aws_dynamodb_table.stock_winners.arn
    }]
  })
}

# ── EventBridge Lambda ─────────────────────────────────────────────────────────

resource "aws_lambda_function" "event_bridge_lambda" {
  function_name    = "stocks-event-bridge-lambda"
  role             = aws_iam_role.eb_lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = var.event_bridge_lambda_zip_path
  timeout          = 180
  source_code_hash = filebase64sha256(var.event_bridge_lambda_zip_path)

  environment {
    variables = {
      MASSIVE_API_KEY = var.massive_api_key
      DYNAMODB_TABLE  = var.dynamodb_table_name
    }
  }

  tags = {
    Project = "stocks-pipeline"
  }
}

# ── API Gateway Lambda ─────────────────────────────────────────────────────────

resource "aws_lambda_function" "api_gateway_lambda" {
  function_name    = "stocks-api-gateway-lambda"
  role             = aws_iam_role.api_lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = var.api_gateway_lambda_zip_path
  timeout          = 30
  source_code_hash = filebase64sha256(var.api_gateway_lambda_zip_path)

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }

  tags = {
    Project = "stocks-pipeline"
  }
}

# ── EventBridge Rule ───────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "event_bridge_trigger" {
  name                = "stocks-event-bridge-trigger"
  description         = "Fires Mon-Fri at 9 PM EST (02:00 UTC next day / 10 PM EDT in summer). EventBridge runs in UTC."
  schedule_expression = "cron(5 3 ? * TUE-SAT *)"
  state               = "ENABLED"

  tags = {
    Project = "stocks-pipeline"
  }
}

resource "aws_cloudwatch_event_target" "event_bridge_lambda_target" {
  rule      = aws_cloudwatch_event_rule.event_bridge_trigger.name
  target_id = "StocksEventBridgeLambda"
  arn       = aws_lambda_function.event_bridge_lambda.arn

  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 60
  }
}

resource "aws_lambda_function_event_invoke_config" "event_bridge_lambda" {
  function_name          = aws_lambda_function.event_bridge_lambda.function_name
  maximum_retry_attempts = 2
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_bridge_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.event_bridge_trigger.arn
}

# ── API Gateway ────────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "stocks_api" {
  name          = "stocks-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["content-type"]
  }

  tags = {
    Project = "stocks-pipeline"
  }
}

resource "aws_apigatewayv2_integration" "movers_integration" {
  api_id                 = aws_apigatewayv2_api.stocks_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_gateway_lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "movers_route" {
  api_id    = aws_apigatewayv2_api.stocks_api.id
  route_key = "GET /movers"
  target    = "integrations/${aws_apigatewayv2_integration.movers_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.stocks_api.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Project = "stocks-pipeline"
  }
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_gateway_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.stocks_api.execution_arn}/*/*"
}

# ── S3 Frontend ────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "frontend" {
  bucket = "stocks-frontend-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project = "stocks-pipeline"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_policy" "frontend_public" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_s3_object" "frontend_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "frontend/index.html"
  content_type = "text/html"
  etag         = filemd5("frontend/index.html")
}

data "aws_caller_identity" "current" {}

# ── Outputs ────────────────────────────────────────────────────────────────────

output "event_bridge_lambda_name" {
  value = aws_lambda_function.event_bridge_lambda.function_name
}

output "api_gateway_lambda_name" {
  value = aws_lambda_function.api_gateway_lambda.function_name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.stock_winners.name
}

output "event_bridge_rule_name" {
  value = aws_cloudwatch_event_rule.event_bridge_trigger.name
}

output "api_url" {
  description = "GET /movers endpoint — paste this into index.html"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/movers"
}

output "frontend_url" {
  description = "Public URL for the frontend"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}