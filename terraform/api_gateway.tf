# ========================================
# API GATEWAY (HTTP API)
# ========================================

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

# ========================================
# INGESTION ENDPOINT: POST /tickets
# ========================================

resource "aws_apigatewayv2_integration" "ingest_integration" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ingest.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_tickets" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /tickets"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_integration.id}"
}

resource "aws_lambda_permission" "allow_apigw_ingest" {
  statement_id  = "AllowAPIGatewayIngest"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# ========================================
# DASHBOARD ENDPOINTS: GET /tickets/*
# ========================================

resource "aws_apigatewayv2_integration" "dashboard_integration" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dashboard_api.invoke_arn
  payload_format_version = "2.0"
}

# GET /tickets - list all tickets
resource "aws_apigatewayv2_route" "get_tickets" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /tickets"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard_integration.id}"
}

# GET /tickets/stats - ticket statistics
resource "aws_apigatewayv2_route" "get_stats" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /tickets/stats"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard_integration.id}"
}

# GET /tickets/sla-breaches - SLA breach report
resource "aws_apigatewayv2_route" "get_sla_breaches" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /tickets/sla-breaches"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard_integration.id}"
}

# GET /tickets/{id} - single ticket details
resource "aws_apigatewayv2_route" "get_ticket_by_id" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /tickets/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard_integration.id}"
}

# PUT /tickets/{id}/resolve - resolve a ticket
resource "aws_apigatewayv2_route" "resolve_ticket" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "PUT /tickets/{id}/resolve"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard_integration.id}"
}

resource "aws_lambda_permission" "allow_apigw_dashboard" {
  statement_id  = "AllowAPIGatewayDashboard"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
