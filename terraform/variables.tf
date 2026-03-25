variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "ai-support-automator"
}

variable "notification_email" {
  description = "Email for SNS notifications"
  type        = string
}

variable "sla_critical_minutes" {
  description = "SLA for critical tickets in minutes. Demo: 5, Production: 60"
  type        = number
  default     = 5
}

variable "sla_high_minutes" {
  description = "SLA for high priority tickets in minutes. Demo: 15, Production: 240"
  type        = number
  default     = 15
}

variable "sla_medium_minutes" {
  description = "SLA for medium priority tickets in minutes. Demo: 30, Production: 1440"
  type        = number
  default     = 30
}

variable "sla_low_minutes" {
  description = "SLA for low priority tickets in minutes. Demo: 60, Production: 4320"
  type        = number
  default     = 60
}

variable "firehose_buffer_seconds" {
  description = "Firehouse buffer interval. Demo: 60, Production: 300"
  type        = number
  default     = 60
}

variable "sla_check_interval_minutes" {
  description = "How often to check SLA breaches. Demo: 5, Production: 60"
  type        = number
  default     = 5
}
