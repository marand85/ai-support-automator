terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ========================================
# S3 BUCKETS
# ========================================

# Raw ticket archive (Firehouse destination)
resource "aws_s3_bucket" "ticket_archive" {
  bucket = "${var.project_name}-archive-${random_id.suffix.hex}"
}

# ========================================
# KINESIS DATA STREAMS (real-time ingestion)
# ========================================

resource "aws_kinesis_stream" "tickets" {
  name             = "${var.project_name}-ticket-stream"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

# ========================================
# KINESIS DATA FIREHOSE (raw archive to S3)
# ========================================

resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-role"
  assume_role_policy = jsonencode({
    Verision = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "${var.project_name}-firehose-policy"
  role = aws_iam_role.firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.ticket_archive.arn,
          "${aws_s3_bucket.ticket_archive.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.tickets.arn
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "ticket_archive" {
  name        = "${var.project_name}-archive-delivery"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.tickets.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_role.arn
    bucket_arn          = aws_s3_bucket.ticket_archive.arn
    prefix              = "raw-tickets/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/"
    buffering_interval  = var.firehose_buffer_seconds
    buffering_size      = 1
  }
}

# ========================================
# SQS QUEUES (decoupling + error handling)
# ========================================

resource "aws_sqs_queue" "ticket_dlq" {
  name                      = "${var.project_name}-ticket-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "ticket_processing" {
  name                       = "${var.project_name}-ticket-queue"
  visibility_timeout_seconds = 300   # 5 min (must be > Step Functions duration)
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ticket_dlq.arn
    maxReceiveCount     = 3
  })
}

# ========================================
# DYNAMODB (ticket storage + SLA tracking)
# ========================================

resource "aws_dynamodb_table" "tickets" {
  name         = "${var.project_name}-tickets"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ticket_id"

  attribute {
    name = "ticket_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "status-created-index"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }
}

# ========================================
# SNS TOPICS (notifications)
# ========================================

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Critical tickets get separate topic for immediate attention
resource "aws_sns_topic" "critical_alerts" {
  name = "${var.project_name}-critical-alerts"
}

resource "aws_sns_topic_subscription" "critical_email" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ========================================
# IAM ROLE (shared Lambda execution role)
# ========================================

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ]
        Resource = "aws_kinesis_stream.tickets_arn"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.ticket_processing.arn,
          aws_sqs_queue.ticket_dlq.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.tickets.arn,
          "${aws_dynamodb_table.tickets.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = [
          aws_sns_topic.alerts.arn,
          aws_sns_topic.critical_alerts.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = "*"
      }
    ]
  })
}
