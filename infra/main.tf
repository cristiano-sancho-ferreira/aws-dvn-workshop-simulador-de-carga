# ============================================================
# Locals
# ============================================================

locals {
  name_prefix = "${var.organization_name}-${var.application_name}-${var.environment}"
  bucket_name = local.name_prefix
  common_tags = merge(
    var.common_tags,
    {
      Organization = var.organization_name
      Environment  = var.environment
      Application  = var.application_name
      Project      = "dvn-workshop"
    }
  )
}

# ============================================================
# Módulo Frontend (S3 + CloudFront + Cognito)
# ============================================================

module "frontend" {
  source = "./modules/backend"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  region            = var.region
  environment       = var.environment
  application_name  = var.application_name
  organization_name = var.organization_name
  bucket_name       = local.bucket_name
  name_prefix       = local.name_prefix
  common_tags       = local.common_tags
}
