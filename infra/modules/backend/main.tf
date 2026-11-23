# ============================================================
# Bucket S3
# ============================================================

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
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

resource "aws_api_gateway_resource" "runs" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "runs"
}

resource "aws_api_gateway_method" "runs_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.runs.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "runs_options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.runs.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "runs_options" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.runs.id
  http_method      = aws_api_gateway_method.runs_options.http_method
  type             = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "runs_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs.id
  http_method = aws_api_gateway_method.runs_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "runs_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs.id
  http_method = aws_api_gateway_method.runs_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_method_response.runs_options_200]
}

resource "aws_api_gateway_integration" "runs_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.runs.id
  http_method             = aws_api_gateway_method.runs_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.controller.invoke_arn
}

resource "aws_api_gateway_method" "runs_get" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.runs.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "runs_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.runs.id
  http_method             = aws_api_gateway_method.runs_get.http_method
  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.controller.invoke_arn
}

resource "aws_api_gateway_method_response" "runs_get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs.id
  http_method = aws_api_gateway_method.runs_get.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "runs_get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs.id
  http_method = aws_api_gateway_method.runs_get.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.runs_get]
}

resource "aws_api_gateway_resource" "runs_runid" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.runs.id
  path_part   = "{runid}"
}

resource "aws_api_gateway_method" "runs_runid_get" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.runs_runid.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "runs_runid_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.runs_runid.id
  http_method             = aws_api_gateway_method.runs_runid_get.http_method
  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.controller.invoke_arn
}

resource "aws_api_gateway_method" "runs_runid_options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.runs_runid.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "runs_runid_options" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.runs_runid.id
  http_method      = aws_api_gateway_method.runs_runid_options.http_method
  type             = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "runs_runid_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs_runid.id
  http_method = aws_api_gateway_method.runs_runid_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "runs_runid_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs_runid.id
  http_method = aws_api_gateway_method.runs_runid_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_method_response.runs_runid_options_200]
}

resource "aws_api_gateway_method_response" "runs_runid_get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs_runid.id
  http_method = aws_api_gateway_method.runs_runid_get.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "runs_runid_get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs_runid.id
  http_method = aws_api_gateway_method.runs_runid_get.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.runs_runid_get]
}


# ============================================================
# Integração API Gateway → SQS para POST /orders
# Publica mensagens direto na fila FIFO sem passar por Lambda.
# ============================================================
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "orders"
}


resource "aws_api_gateway_method" "orders_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "orders_options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "orders_options" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.orders.id
  http_method      = aws_api_gateway_method.orders_options.http_method
  type             = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "orders_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "orders_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_method_response.orders_options_200]
}

resource "aws_api_gateway_integration" "orders_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.orders_post.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  # Path override  
  uri         = "arn:aws:apigateway:${var.region}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.this.name}"
  credentials             = aws_iam_role.api_gateway.arn

  request_templates = {
    "application/json" = <<EOF
Action=SendMessage&QueueUrl=$util.urlEncode('${aws_sqs_queue.this.url}')&MessageBody=$util.urlEncode($input.body)&MessageGroupId=$input.json('$.shard')
EOF
  }
}

resource "aws_api_gateway_method_response" "orders_post_202" {
  rest_api_id       = aws_api_gateway_rest_api.this.id
  resource_id       = aws_api_gateway_resource.orders.id
  http_method       = aws_api_gateway_method.orders_post.http_method
  status_code       = "202"
  response_models   = { "application/json" = "Empty" }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "orders_post_202" {
  rest_api_id       = aws_api_gateway_rest_api.this.id
  resource_id       = aws_api_gateway_resource.orders.id
  http_method       = aws_api_gateway_method.orders_post.http_method
  status_code       = aws_api_gateway_method_response.orders_post_202.status_code
  response_templates = {
    "application/json" = <<EOF
{
  "accepted": true,
  "messageId": "$util.xpath('/*[local-name()=\"SendMessageResponse\"]/*[local-name()=\"SendMessageResult\"]/*[local-name()=\"MessageId\"]/text()', $input.path('$'))"
}
EOF
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.orders_post]
}


resource "aws_api_gateway_resource" "orders_batch" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "batch"
}


resource "aws_api_gateway_method" "orders_batch_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders_batch.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "orders_batch_options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders_batch.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "orders_batch_options" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.orders_batch.id
  http_method      = aws_api_gateway_method.orders_batch_options.http_method
  type             = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "orders_batch_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders_batch.id
  http_method = aws_api_gateway_method.orders_batch_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "orders_batch_options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders_batch.id
  http_method = aws_api_gateway_method.orders_batch_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_method_response.orders_batch_options_200]
}

resource "aws_api_gateway_integration" "orders_batch_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.orders_batch.id
  http_method             = aws_api_gateway_method.orders_batch_post.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.this.name}"
  credentials             = aws_iam_role.api_gateway.arn

  request_templates = {
    "application/json" = <<EOF
Action=SendMessage&QueueUrl=$util.urlEncode('${aws_sqs_queue.this.url}')&MessageBody=$util.urlEncode($input.body)&MessageGroupId=$input.json('$.shard')
EOF
  }
}


resource "aws_api_gateway_method_response" "orders_batch_post_202" {
  rest_api_id       = aws_api_gateway_rest_api.this.id
  resource_id       = aws_api_gateway_resource.orders_batch.id
  http_method       = aws_api_gateway_method.orders_batch_post.http_method
  status_code       = "202"
  response_models   = { "application/json" = "Empty" }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "orders_batch_post_202" {
  rest_api_id       = aws_api_gateway_rest_api.this.id
  resource_id       = aws_api_gateway_resource.orders_batch.id
  http_method       = aws_api_gateway_method.orders_batch_post.http_method
  status_code       = aws_api_gateway_method_response.orders_batch_post_202.status_code
  response_templates = {
    "application/json" = <<EOF
{
  "accepted": true,
  "messageId": "$util.xpath('/*[local-name()=\"SendMessageResponse\"]/*[local-name()=\"SendMessageResult\"]/*[local-name()=\"MessageId\"]/text()', $input.path('$'))"
}
EOF
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.orders_batch_post]
}


resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.runs_post,
      aws_api_gateway_method.runs_get,
      aws_api_gateway_method.runs_runid_get,
      aws_api_gateway_method.orders_post,
      aws_api_gateway_method.orders_batch_post,
      aws_api_gateway_integration.runs_post,
      aws_api_gateway_integration.runs_get,
      aws_api_gateway_integration.runs_runid_get,
      aws_api_gateway_integration.orders_post,
      aws_api_gateway_integration.orders_batch_post,
      aws_api_gateway_integration.runs_options,
      aws_api_gateway_integration.runs_runid_options,
      aws_api_gateway_integration.orders_options,
      aws_api_gateway_integration.orders_batch_options,
      aws_api_gateway_integration_response.orders_post_202,
      aws_api_gateway_integration_response.orders_batch_post_202,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"
  
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-api_gateway" })
}

resource "aws_api_gateway_api_key" "this" {
  name    = "${var.name_prefix}-key"
  enabled = true

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-api_gateway" })
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.name_prefix}-usage-plan"
  description = "Plano de uso do ${var.name_prefix}"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    rate_limit  = 2000   # requisições/segundo (média)
    burst_limit = 400   # pico
  }

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-api_gateway" })
}

resource "aws_api_gateway_usage_plan_key" "this" {
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}

output "api_key_value" {
  value     = aws_api_gateway_api_key.this.value
  sensitive = true
}

resource "aws_api_gateway_model" "order" {
  rest_api_id  = aws_api_gateway_rest_api.this.id
  name         = "Order"
  content_type = "application/json"
  description  = " orders request payload"
  schema       = <<EOF
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "type": "object",
  "required": [
    "runId",
    "orderId",
    "shard"
  ],
  "additionalProperties": false,
  "properties": {
    "runId": {
      "type": "string",
      "pattern": "^[a-f0-9-]{36}$"
    },
    "orderId": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9_-]{1,100}$"
    },
    "shard": {
      "type": "integer",
      "minimum": 0,
      "maximum": 1023
    },
    "sentAt": {
      "type": "integer",
      "minimum": 0
    }
  }
}
EOF
}

resource "aws_api_gateway_model" "order_batch" {
  rest_api_id  = aws_api_gateway_rest_api.this.id
  name         = "OrderBatch"
  content_type = "application/json"
  description  = " orders request payload"
  schema       = <<EOF
{
  {
  "$schema": "http://json-schema.org/draft-04/schema#",
  "type": "object",
  "required": [
    "orders"
  ],
  "additionalProperties": false,
  "properties": {
    "orders": {
      "type": "array",
      "minItems": 1,
      "maxItems": 10,
      "items": {
        "type": "object",
        "required": [
          "runId",
          "orderId",
          "shard"
        ],
        "additionalProperties": false,
        "properties": {
          "runId": {
            "type": "string",
            "pattern": "^[a-f0-9-]{36}$"
          },
          "orderId": {
            "type": "string",
            "pattern": "^[a-zA-Z0-9_-]{1,100}$"
          },
          "shard": {
            "type": "integer",
            "minimum": 0,
            "maximum": 1023
          },
          "sentAt": {
            "type": "integer",
            "minimum": 0
          }
        }
      }
    }
  }
}
EOF
}


# resource "aws_api_gateway_deployment" "this" {
#   depends_on = [
#     aws_api_gateway_integration.pedidos
#   ]

#   rest_api_id = aws_api_gateway_rest_api.this.id
#   # stage_name  = "prod"
# }



resource "aws_iam_role" "api_gateway" {
  name = "${var.name_prefix}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-api_gateway-role" })
}

resource "aws_iam_role_policy" "api_gateway" {
  name = "${var.name_prefix}-api-gateway-policy"
  role = aws_iam_role.api_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [
          aws_sqs_queue.this.arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.controller.arn
        ]
      }
    ]
  })
}

# ============================================================
# Lambda permissions para API Gateway
# ============================================================

resource "aws_lambda_permission" "api_gateway_controller" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.controller.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}