# ============================================================
# Bucket S3
# ============================================================

resource "aws_s3_bucket" "this" {
  bucket        = "${var.name_prefix}-waf"
  force_destroy = true
  tags          = merge(var.common_tags, { Name = var.bucket_name })
}

# Política do bucket: nega tudo, exceto leitura vinda da distribuição CloudFront abaixo.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}





# ============================================================
# WAFv2 (escopo CloudFront)
# WAFs associados ao CloudFront precisam estar em us-east-1.
# ============================================================

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name_prefix}-waf"
  description = "WAF do CloudFront do workshop DVN"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "dvnWorkshopWaf"
    sampled_requests_enabled   = true
  }

  tags = var.common_tags
}

# ============================================================
# Distribuição CloudFront
# ============================================================

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = ""
  tags                = merge(var.common_tags, { Name = var.name_prefix })

  # WAF associado diretamente aqui — é a única forma suportada para CloudFront.
  # aws_wafv2_web_acl_association não funciona com distribuições CloudFront.
  web_acl_id = aws_wafv2_web_acl.this.arn

  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Cache "managed" da AWS otimizado para conteúdo estático (CachingOptimized)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # SPA: qualquer rota que não exista no S3 (403/404) cai no index.html
  # com status 200, pra o React Router (se você adicionar) cuidar da rota no client.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Origin Access Control: permite que só esta distribuição CloudFront
# específica leia objetos do bucket (substitui o antigo OAI).
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name_prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ============================================================
# Site estático (upload de site/dist para o bucket)
# O buildspec gera o build do site em site/dist/ antes do terraform.
# O fileset varre recursivamente (inclui a pasta assets/) e cada arquivo
# vira um aws_s3_object; arquivos que saem do build são removidos no apply.
# ============================================================

locals {
  site_dir   = "${path.module}/../../../site/dist"
  site_files = fileset(local.site_dir, "**/*")
  mime_types = {
    ".html"  = "text/html"
    ".js"    = "application/javascript"
    ".mjs"   = "application/javascript"
    ".css"   = "text/css"
    ".json"  = "application/json"
    ".map"   = "application/json"
    ".svg"   = "image/svg+xml"
    ".png"   = "image/png"
    ".jpg"   = "image/jpeg"
    ".jpeg"  = "image/jpeg"
    ".gif"   = "image/gif"
    ".webp"  = "image/webp"
    ".ico"   = "image/x-icon"
    ".woff"  = "font/woff"
    ".woff2" = "font/woff2"
    ".ttf"   = "font/ttf"
    ".otf"   = "font/otf"
    ".txt"   = "text/plain"
    ".xml"   = "application/xml"
    ".pdf"   = "application/pdf"
  }
}

resource "aws_s3_object" "site" {
  for_each = local.site_files

  bucket       = aws_s3_bucket.this.id
  key          = each.value
  source       = "${local.site_dir}/${each.value}"
  etag         = filemd5("${local.site_dir}/${each.value}")
  content_type = lookup(local.mime_types, try(regex("\\.[^.]+$", each.value), ""), "application/octet-stream")

  tags = var.common_tags
}

# ============================================================
# Zips das Lambdas
# O buildspec gera os zips em backend/dist/ (raiz do repositório).
# A partir deste módulo (infra/modules/backend), sobem tres niveis ate a
# raiz e entra em backend/dist.
# ============================================================

locals {
  zip_dir = "${path.module}/../../../backend/dist"
}

# ============================================================
# Funções Lambda
# ============================================================

resource "aws_lambda_function" "controller" {
  function_name    = "${var.name_prefix}-controller"
  role             = aws_iam_role.controller.arn
  handler          = "index.handler"
  runtime          = "nodejs26.x"
  filename         = "${local.zip_dir}/lambda-controller.zip"
  source_code_hash = filebase64sha256("${local.zip_dir}/lambda-controller.zip")
  timeout          = 10

  environment {
    variables = {
      TABLE     = "dvn-workshop-table"
      GENERATOR = aws_lambda_function.generator.function_name
      QUEUE     = aws_sqs_queue.this.url
      DLQ       = aws_sqs_queue.dlq.url
    }
  }
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-controller" })
}


resource "aws_lambda_function" "generator" {
  function_name    = "${var.name_prefix}-generator"
  role             = aws_iam_role.generator.arn
  handler          = "index.handler"
  runtime          = "nodejs26.x"
  filename         = "${local.zip_dir}/lambda-generator.zip"
  source_code_hash = filebase64sha256("${local.zip_dir}/lambda-generator.zip")
  timeout          = 10

  environment {
    variables = {
      TABLE = "dvn-workshop-table"
    }
  }
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-generator" })
}


resource "aws_lambda_function" "processor" {
  function_name    = "${var.name_prefix}-processor"
  role             = aws_iam_role.processor.arn
  handler          = "index.handler"
  runtime          = "nodejs26.x"
  filename         = "${local.zip_dir}/lambda-processor.zip"
  source_code_hash = filebase64sha256("${local.zip_dir}/lambda-processor.zip")
  timeout          = 10

  environment {
    variables = {
      TABLE = "dvn-workshop-table"
    }
  }
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-processor" })
}

# ============================================================
# IAM — Lambda controller
# ============================================================

resource "aws_iam_role" "controller" {
  name = "${var.name_prefix}-controller-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
      }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "controller" {
  name = "${var.name_prefix}-controller-lambda-policy"
  role = aws_iam_role.controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.this.arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.this.arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.generator.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "generator" {
  name = "${var.name_prefix}-generator-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "generator" {
  name = "${var.name_prefix}-generator-lambda-policy"
  role = aws_iam_role.generator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:PutItem",
        "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.this.arn
      }
    ]
  })
}

resource "aws_iam_role" "processor" {
  name = "${var.name_prefix}-processor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "processor" {
  name = "${var.name_prefix}-processor-lambda-policy"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.this.arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.this.arn
        ]
      }
    ]
  })
}


# ============================================================
# SQS Fifo
# ============================================================

resource "aws_sqs_queue" "this" {
  name                        = "${var.name_prefix}-pedidos.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "queue"
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 30

  # Após maxReceiveCount tentativas de processamento sem sucesso,
  # a mensagem é automaticamente movida para a DLQ.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-pedidos.fifo" })
}

resource "aws_sqs_queue" "dlq" {
  name                        = "${var.name_prefix}-pedidos-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "queue"
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 30

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-pedidos-dlq.fifo" })
}



# ============================================================
# DynamoDB
# ============================================================

resource "aws_dynamodb_table" "this" {
  name         = "dvn-workshop-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-dvn-workshop-table" })
}



# ============================================================
# API Gateway
# ============================================================

resource "aws_api_gateway_rest_api" "this" {
  name        = var.name_prefix
  description = "API Gateway para o ${var.name_prefix}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-api" })
}

resource "aws_api_gateway_resource" "pedidos" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "runs"
}

resource "aws_api_gateway_method" "pedidos_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.pedidos.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "pedidos_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.pedidos.id
  http_method             = aws_api_gateway_method.pedidos_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.controller.invoke_arn
}

resource "aws_api_gateway_method" "pedidos_get" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.pedidos.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "pedidos_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.pedidos.id
  http_method             = aws_api_gateway_method.pedidos_get.http_method
  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.controller.invoke_arn
}

resource "aws_api_gateway_resource" "pedidos" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.pedidos.id
  path_part   = "{runid}"
}




# resource "aws_api_gateway_deployment" "this" {
#   depends_on = [
#     aws_api_gateway_integration.pedidos
#   ]

#   rest_api_id = aws_api_gateway_rest_api.this.id
#   # stage_name  = "prod"
# }


