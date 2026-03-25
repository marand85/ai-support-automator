# ========================================
# STEP FUNCTIONS - IAM ROLE
# ========================================

resource "aws_iam_role" "step_functions_role" {
  name = "${var.project_name}-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${var.project_name}-sfn-policy"
  role = aws_iam_role.step_functions_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        aws_lambda_function.ai_classify.arn,
        aws_lambda_function.ai_generate.arn,
        aws_lambda_function.store_result.arn,
        aws_lambda_function.critical_alert.arn,
        aws_lambda_function.notify_customer.arn,
        aws_lambda_function.error_handler.arn
      ]
    }]
  })
}

# ========================================
# STEP FUNCTIONS - STATE MACHINE
# ========================================

resource "aws_sfn_state_machine" "ticket_processor" {
  name     = "${var.project_name}-workflow"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "AI Support Ticket Processing Workflow"
    StartAt = "ClassifyTicket"

    States = {

      # Step 1: Claude classifies urgency + category
      ClassifyTicket = {
        Type     = "Task"
        Resource = aws_lambda_function.ai_classify.arn
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 5
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "CheckUrgency"
      }

      # Step 2: Branch based on urgency
      CheckUrgency = {
        Type = "Choice"
        Choices = [{
          Variable     = "$.classification.urgency"
          StringEquals = "critical"
          Next         = "CriticalPath"
        }]
        Default = "GenerateResponse"
      }

      # Step 3a: Critical tickets - parallel: alert + generate response
      CriticalPath = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "SendCriticalAlert"
            States = {
              SendCriticalAlert = {
                Type     = "Task"
                Resource = aws_lambda_function.critical_alert.arn
                End      = true
              }
            }
          },
          {
            StartAt = "GenerateCriticalResponse"
            States = {
              GenerateCriticalResponse = {
                Type     = "Task"
                Resource = aws_lambda_function.ai_generate.arn
                End      = true
              }
            }
          }
        ]
        ResultPath = "$.parallel_results"
        Next       = "MergeCriticalResults"
      }

      # Step 3a-merge: Combine parallel results
      MergeCriticalResults = {
        Type = "Pass"
        Parameters = {
          "ticket.$"         = "$.ticket"
          "classification.$" = "$.classification"
          "ai_response.$"    = "$.parallel_results[1].ai_response"
          "critical_alert.$" = "$.parallel_results[0]"
        }
        Next = "StoreResult"
      }

      # Step 3b: Normal tickets - generate response
      GenerateResponse = {
        Type     = "Task"
        Resource = aws_lambda_function.ai_generate.arn
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 5
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "StoreResult"
      }

      # Step 4: Save everything to DynamoDB
      StoreResult = {
        Type     = "Task"
        Resource = aws_lambda_function.store_result.arn
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 3
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "NotifyCustomer"
      }

      # Step 5: Send confirmation to customer
      NotifyCustomer = {
        Type     = "Task"
        Resource = aws_lambda_function.notify_customer.arn
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 3
          MaxAttempts     = 1
          BackoffRate     = 1.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        End = true
      }

      # Error handler: log error + store failed ticket
      HandleError = {
        Type     = "Task"
        Resource = aws_lambda_function.error_handler.arn
        End      = true
      }
    }
  })
}