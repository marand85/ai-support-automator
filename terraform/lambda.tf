# ========================================
# LAMBDA ZIP PACKAGES
# ========================================

data "archive_file" "ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/ingest"
  output_path = "${path.module}/lambda_ingest.zip"
}

data "archive_file" "stream_processor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/stream_processor"
  output_path = "${path.module}/lambda_stream_processor.zip"
}

data "archive_file" "workflow_trigger_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/workflow_trigger"
  output_path = "${path.module}/lambda_workflow_trigger.zip"
}

data "archive_file" "ai_processor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/ai_processor"
  output_path = "${path.module}/lambda_ai_processor.zip"
}

data "archive_file" "ticket_operations_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/ticket_operations"
  output_path = "${path.module}/lambda_ticket_operations.zip"
}

data "archive_file" "dashboard_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/dashboard_api"
  output_path = "${path.module}/lambda_dashboard_api.zip"
}

data "archive_file" "sla_checker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/sla_checker"
  output_path = "${path.module}/lambda_sla_checker.zip"
}

# ========================================
# LAMBDA FUNCTIONS
# ========================================

# --- Ingest: API Gateway → validate → Kinesis ---
resource "aws_lambda_function" "ingest" {
  filename         = data.archive_file.ingest_zip.output_path
  function_name    = "${var.project_name}-ingest"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.ingest_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      KINESIS_STREAM_NAME = aws_kinesis_stream.tickets.name
    }
  }
}

# --- Stream Processor: Kinesis → SQS ---
resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.stream_processor_zip.output_path
  function_name    = "${var.project_name}-stream-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.stream_processor_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.ticket_processing.url
    }
  }
}

# --- Workflow Trigger: SQS → Start Step Functions ---
resource "aws_lambda_function" "workflow_trigger" {
  filename         = data.archive_file.workflow_trigger_zip.output_path
  function_name    = "${var.project_name}-workflow-trigger"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.workflow_trigger_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.ticket_processor.arn
    }
  }
}

# --- AI Classify: Claude classifies ticket ---
resource "aws_lambda_function" "ai_classify" {
  filename         = data.archive_file.ai_processor_zip.output_path
  function_name    = "${var.project_name}-ai-classify"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.classify_ticket"
  source_code_hash = data.archive_file.ai_processor_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      ANTHROPIC_API_KEY = var.anthropic_api_key
    }
  }
}

# --- AI Generate Response: Claude generates draft response ---
resource "aws_lambda_function" "ai_generate" {
  filename         = data.archive_file.ai_processor_zip.output_path
  function_name    = "${var.project_name}-ai-generate"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.generate_response"
  source_code_hash = data.archive_file.ai_processor_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      ANTHROPIC_API_KEY = var.anthropic_api_key
    }
  }
}

# --- Store Result: Save to DynamoDB ---
resource "aws_lambda_function" "store_result" {
  filename         = data.archive_file.ticket_operations_zip.output_path
  function_name    = "${var.project_name}-store-result"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.store_result"
  source_code_hash = data.archive_file.ticket_operations_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE   = aws_dynamodb_table.tickets.name
      SLA_CRITICAL_MIN = tostring(var.sla_critical_minutes)
      SLA_HIGH_MIN     = tostring(var.sla_high_minutes)
      SLA_MEDIUM_MIN   = tostring(var.sla_medium_minutes)
      SLA_LOW_MIN      = tostring(var.sla_low_minutes)
    }
  }
}

# --- Critical Alert: SNS notification for critical tickets ---
resource "aws_lambda_function" "critical_alert" {
  filename         = data.archive_file.ticket_operations_zip.output_path
  function_name    = "${var.project_name}-critical-alert"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.send_critical_alert"
  source_code_hash = data.archive_file.ticket_operations_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      SNS_CRITICAL_TOPIC_ARN = aws_sns_topic.critical_alerts.arn
    }
  }
}

# --- Notify Customer: Confirmation to customer ---
resource "aws_lambda_function" "notify_customer" {
  filename         = data.archive_file.ticket_operations_zip.output_path
  function_name    = "${var.project_name}-notify-customer"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.notify_customer"
  source_code_hash = data.archive_file.ticket_operations_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }
}

# --- Error Handler: Store error in DynamoDB ---
resource "aws_lambda_function" "error_handler" {
  filename         = data.archive_file.ticket_operations_zip.output_path
  function_name    = "${var.project_name}-error-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handle_error"
  source_code_hash = data.archive_file.ticket_operations_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.tickets.name
    }
  }
}

# --- Dashboard API: REST queries ---
resource "aws_lambda_function" "dashboard_api" {
  filename         = data.archive_file.dashboard_api_zip.output_path
  function_name    = "${var.project_name}-dashboard-api"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.dashboard_api_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.tickets.name
    }
  }
}

# --- SLA Checker: EventBridge cron ---
resource "aws_lambda_function" "sla_checker" {
  filename         = data.archive_file.sla_checker_zip.output_path
  function_name    = "${var.project_name}-sla-checker"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.sla_checker_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.tickets.name
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }
}

# ========================================
# EVENT SOURCE MAPPINGS (triggers)
# ========================================

# Kinesis → stream_processor Lambda
resource "aws_lambda_event_source_mapping" "kinesis_to_processor" {
  event_source_arn  = aws_kinesis_stream.tickets.arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"
  batch_size        = 10
}

# SQS → workflow_trigger Lambda
resource "aws_lambda_event_source_mapping" "sqs_to_workflow" {
  event_source_arn = aws_sqs_queue.ticket_processing.arn
  function_name    = aws_lambda_function.workflow_trigger.arn
  batch_size       = 1
}