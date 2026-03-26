output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_stage.stage.invoke_url
}

output "kinesis_stream_name" {
  description = "Kinesis Data Stream name"
  value       = aws_kinesis_stream.tickets.name
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.tickets.name
}

output "s3_archive_bucket" {
  description = "S3 bucket for raw ticket archive"
  value       = aws_s3_bucket.ticket_archive.id
}

output "sqs_queue_url" {
  description = "SQS processing queue URL"
  value       = aws_sqs_queue.ticket_processing.url
}

output "sqs_dlq_url" {
  description = "SQS dead letter queue URL"
  value       = aws_sqs_queue.ticket_dlq.url
}

output "step_functions_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.ticket_processor.arn
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "demo_instructions" {
  description = "Demo instructions"
  value       = <<-EOT

    === DEMO INSTRUCTIONS ===

    1. Submit a ticket:
       curl -X POST ${aws_apigatewayv2_stage.stage.invoke_url}tickets \
         -H "Content-Type: application/json" \
         -d '{"channel":"email","subject":"Payment system DOWN","body":"No customers can make payments since 10:00","customer":"acme-corp"}'

    2. Wait ~2-3 minutes for processing

    3. Check results:
       curl ${aws_apigatewayv2_stage.stage.invoke_url}tickets
       curl ${aws_apigatewayv2_stage.stage.invoke_url}tickets/stats
       curl ${aws_apigatewayv2_stage.stage.invoke_url}tickets/sla-breaches

    4. Resolve a ticket:
       curl -X PUT ${aws_apigatewayv2_stage.stage.invoke_url}tickets/TICKET_ID/resolve

    5. View CloudWatch dashboard:
       https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}

    6. Check your email for SNS notifications

    7. IMPORTANT: Run 'terraform destroy' when done to avoid charges (Kinesis costs ~$0.36/day)

  EOT
}
