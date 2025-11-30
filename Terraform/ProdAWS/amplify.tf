resource "aws_amplify_app" "frontend" {
  count = var.enable_amplify ? 1 : 0

  name                     = var.amplify_app_name
  repository               = var.amplify_repo_url
  access_token             = var.amplify_access_token
  enable_branch_auto_build = true

  platform = "WEB_COMPUTE"
}

resource "aws_amplify_branch" "frontend" {
  count = var.enable_amplify ? 1 : 0

  app_id      = aws_amplify_app.frontend[0].id
  branch_name = var.amplify_branch_name
  stage       = "PRODUCTION"
}
