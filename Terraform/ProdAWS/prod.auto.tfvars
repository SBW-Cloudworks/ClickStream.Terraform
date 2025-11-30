# Example production variables (placeholders)
region           = "ap-southeast-1"
aws_profile      = "prod"

# Buckets
bucket_media     = "sbw-clickstream-media-prod"
bucket_raw       = "sbw-clickstream-raw-prod"
bucket_processed = "sbw-clickstream-processed-prod"

# Lambda artifacts (adjust paths to your built ZIPs)
lambda_ingest_zip = "../../artifacts/lambda_ingest.zip"
lambda_etl_zip    = "../../artifacts/lambda_etl.zip"

# Networking / access
enable_nat_gateway  = true
allowed_admin_cidrs = ["203.0.113.0/24"] # who can reach Shiny ALB; set [] to keep closed

# EC2 SSH key pairs (must exist in AWS)
oltp_key_name  = "prod-key"
dwh_key_name   = "prod-key"
shiny_key_name = "prod-key"

# Optional custom AMIs (leave empty to use Amazon Linux 2 latest)
oltp_ami_id  = ""
dwh_ami_id   = ""
shiny_ami_id = ""

# Cognito / SNS
cognito_user_pool_name = "clickstream-users"
cognito_client_name    = "clickstream-app-client"
sns_topic_name         = "clickstream-prod-alerts"

# Amplify (enabled by default; set to false if unused)
enable_amplify       = true
amplify_repo_url     = "https://github.com/example-org/example-repo"
amplify_access_token = "REPLACE_WITH_GH_PAT"
amplify_branch_name  = "main"

# Log retention (days)
log_retention_days = 30
