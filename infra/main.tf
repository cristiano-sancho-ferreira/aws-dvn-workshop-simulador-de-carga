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
      Application  = "million-orders-60s"
      Project      = "dvn-workshop"
    }

  )
}

# ============================================================
# Módulo Backend (S3 + CloudFront + Lambda)
# ============================================================

module "backend" {
  source = "./modules/backend"
  region            = var.region
  environment       = var.environment
  application_name  = "million-orders-60s"
  organization_name = var.organization_name
  bucket_name       = local.bucket_name
  name_prefix       = local.name_prefix
  common_tags       = local.common_tags
}
