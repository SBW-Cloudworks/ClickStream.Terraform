variable "region" {
  description = "AWS region for the production deployment."
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name. Leave empty to use default credentials chain."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Whether to provision a NAT Gateway for private subnet egress."
  type        = bool
  default     = true
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to reach admin endpoints (e.g., R Shiny via ALB)."
  type        = list(string)
  default     = []
}

variable "bucket_media" {
  description = "Media/assets bucket name."
  type        = string
}

variable "bucket_raw" {
  description = "Raw clickstream bucket name."
  type        = string
}

variable "bucket_processed" {
  description = "Processed clickstream bucket name."
  type        = string
}

variable "sns_topic_name" {
  description = "Alerts topic name."
  type        = string
  default     = "clickstream-prod-alerts"
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions."
  type        = string
  default     = "python3.10"
}

variable "lambda_handler" {
  description = "Default handler for packaged lambdas."
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "lambda_memory_mb" {
  description = "Memory size for Lambda functions."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Timeout for Lambda functions."
  type        = number
  default     = 30
}

variable "lambda_ingest_zip" {
  description = "Path to ingest lambda zip."
  type        = string
}

variable "lambda_etl_zip" {
  description = "Path to ETL lambda zip."
  type        = string
}

variable "lambda_extra_environment" {
  description = "Additional environment variables to inject into both Lambdas."
  type        = map(string)
  default     = {}
}

variable "api_name" {
  description = "Name for the API Gateway REST API."
  type        = string
  default     = "clickstream-api"
}

variable "api_stage" {
  description = "Stage name for API Gateway deployment."
  type        = string
  default     = "prod"
}

variable "etl_schedule_expression" {
  description = "EventBridge schedule for ETL."
  type        = string
  default     = "cron(0 * * * ? *)"
}

variable "cognito_user_pool_name" {
  description = "Cognito user pool name."
  type        = string
  default     = "clickstream-users"
}

variable "cognito_client_name" {
  description = "Cognito user pool client name."
  type        = string
  default     = "clickstream-app-client"
}

variable "enable_amplify" {
  description = "Whether to provision an Amplify app for the frontend."
  type        = bool
  default     = true
}

variable "amplify_app_name" {
  description = "Amplify app name."
  type        = string
  default     = "clickstream-frontend"
}

variable "amplify_repo_url" {
  description = "Repository URL for Amplify (HTTPS). Required when enable_amplify is true."
  type        = string
  default     = ""
}

variable "amplify_access_token" {
  description = "Personal access token for Amplify to access the repo."
  type        = string
  default     = ""
  sensitive   = true
}

variable "amplify_branch_name" {
  description = "Branch to connect in Amplify."
  type        = string
  default     = "main"
}

variable "oltp_instance_type" {
  description = "Instance type for the OLTP EC2."
  type        = string
  default     = "t3.medium"
}

variable "dwh_instance_type" {
  description = "Instance type for the Data Warehouse EC2."
  type        = string
  default     = "t3.large"
}

variable "shiny_instance_type" {
  description = "Instance type for the R Shiny EC2."
  type        = string
  default     = "t3.large"
}

variable "oltp_ami_id" {
  description = "AMI ID override for OLTP EC2."
  type        = string
  default     = ""
}

variable "dwh_ami_id" {
  description = "AMI ID override for DWH EC2."
  type        = string
  default     = ""
}

variable "shiny_ami_id" {
  description = "AMI ID override for Shiny EC2."
  type        = string
  default     = ""
}

variable "oltp_key_name" {
  description = "SSH key pair name for OLTP EC2."
  type        = string
  default     = ""
}

variable "dwh_key_name" {
  description = "SSH key pair name for DWH EC2."
  type        = string
  default     = ""
}

variable "shiny_key_name" {
  description = "SSH key pair name for Shiny EC2."
  type        = string
  default     = ""
}

variable "oltp_root_volume_gb" {
  description = "Root volume size for OLTP EC2."
  type        = number
  default     = 50
}

variable "dwh_root_volume_gb" {
  description = "Root volume size for DWH EC2."
  type        = number
  default     = 200
}

variable "shiny_root_volume_gb" {
  description = "Root volume size for Shiny EC2."
  type        = number
  default     = 100
}

variable "oltp_port" {
  description = "Port for the OLTP database."
  type        = number
  default     = 5432
}

variable "dwh_port" {
  description = "Port for the Data Warehouse."
  type        = number
  default     = 5432
}

variable "shiny_port" {
  description = "Port for R Shiny service."
  type        = number
  default     = 3838
}

variable "shiny_user_data" {
  description = "User data script for R Shiny EC2."
  type        = string
  default     = <<-EOT
    #!/bin/bash
    echo "Placeholder user-data for Shiny instance. Replace with R/Shiny install steps." > /var/log/shiny-user-data.log
  EOT
}

variable "enable_shiny_alb" {
  description = "Whether to front Shiny with an internal ALB."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention (days) for CloudWatch Log Groups created here."
  type        = number
  default     = 30
}

variable "extra_tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
