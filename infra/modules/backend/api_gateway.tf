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

resource "aws_api_gateway_gateway_response" "default_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "DEFAULT_4XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

resource "aws_api_gateway_gateway_response" "default_5xx" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "DEFAULT_5XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

resource "aws_api_gateway_resource" "runs" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "runs"
}

resource "aws_api_gateway_method" "runs_post" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.runs.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "runs_options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.runs.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "runs_options" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs.id
  http_method = aws_api_gateway_method.runs_options.http_method
  type        = "MOCK"
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
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.runs.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "runs_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.runs.id
  http_method             = aws_api_gateway_method.runs_get.http_method
  integration_http_method = "POST"
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
  path_part   = "{runId}"
}

resource "aws_api_gateway_method" "runs_runid_get" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.runs_runid.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "runs_runid_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.runs_runid.id
  http_method             = aws_api_gateway_method.runs_runid_get.http_method
  integration_http_method = "POST"
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
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.runs_runid.id
  http_method = aws_api_gateway_method.runs_runid_options.http_method
  type        = "MOCK"
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
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.orders.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
  request_models   = { "application/json" = aws_api_gateway_model.order.name }
}

resource "aws_api_gateway_method" "orders_options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "orders_options" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_options.http_method
  type        = "MOCK"
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
  credentials = aws_iam_role.api_gateway.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = <<EOF
Action=SendMessage
&MessageBody=$util.urlEncode($input.body)
&MessageGroupId=$util.urlEncode($input.path("$.runId"))-$util.urlEncode($input.path("$.shard"))
&MessageDeduplicationId=$util.urlEncode($input.path("$.orderId"))
EOF
  }
}

resource "aws_api_gateway_method_response" "orders_post_202" {
  rest_api_id     = aws_api_gateway_rest_api.this.id
  resource_id     = aws_api_gateway_resource.orders.id
  http_method     = aws_api_gateway_method.orders_post.http_method
  status_code     = "202"
  response_models = { "application/json" = "Empty" }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "orders_post_202" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method
  status_code = aws_api_gateway_method_response.orders_post_202.status_code
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
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.orders_batch.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
  request_models   = { "application/json" = aws_api_gateway_model.order_batch.name }
}

resource "aws_api_gateway_method" "orders_batch_options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders_batch.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "orders_batch_options" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders_batch.id
  http_method = aws_api_gateway_method.orders_batch_options.http_method
  type        = "MOCK"
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

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-amz-json-1.0'"
    "integration.request.header.X-Amz-Target" = "'AmazonSQS.SendMessageBatch'"
  }

  request_templates = {
    "application/json" = <<EOF
{
  "QueueUrl": "https://sqs.${var.region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.this.name}",
  "Entries": [
#foreach($order in $input.path('$.orders'))
  #set($path = "$.orders[$foreach.index]")
  #set($runId = $order.runId)
  #set($shard = $order.shard)
    {
      "Id": "$foreach.index",
      "MessageBody": "$util.escapeJavaScript($input.json($path)).replaceAll("\\'","'")",
      "MessageGroupId": "$${runId}-$${shard}",
      "MessageDeduplicationId": "$order.orderId"
    }#if($foreach.hasNext),#end
#end
  ]
}
EOF
  }
}


resource "aws_api_gateway_method_response" "orders_batch_post_202" {
  rest_api_id     = aws_api_gateway_rest_api.this.id
  resource_id     = aws_api_gateway_resource.orders_batch.id
  http_method     = aws_api_gateway_method.orders_batch_post.http_method
  status_code     = "202"
  response_models = { "application/json" = "Empty" }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "orders_batch_post_502" {
  rest_api_id     = aws_api_gateway_rest_api.this.id
  resource_id     = aws_api_gateway_resource.orders_batch.id
  http_method     = aws_api_gateway_method.orders_batch_post.http_method
  status_code     = "502"
  response_models = { "application/json" = "Empty" }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "orders_batch_post_202" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.orders_batch.id
  http_method = aws_api_gateway_method.orders_batch_post.http_method
  status_code = aws_api_gateway_method_response.orders_batch_post_202.status_code
  response_templates = {
    "application/json" = "$input.body"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.orders_batch_post]
}

resource "aws_api_gateway_integration_response" "orders_batch_post_502" {
  rest_api_id       = aws_api_gateway_rest_api.this.id
  resource_id       = aws_api_gateway_resource.orders_batch.id
  http_method       = aws_api_gateway_method.orders_batch_post.http_method
  status_code       = aws_api_gateway_method_response.orders_batch_post_502.status_code
  selection_pattern = "[45][0-9][0-9]"
  response_templates = {
    "application/json" = "$input.body"
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
      aws_api_gateway_resource.runs_runid.path_part,
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
      {
        status_code         = aws_api_gateway_method_response.orders_batch_post_502.status_code
        response_models     = aws_api_gateway_method_response.orders_batch_post_502.response_models
        response_parameters = aws_api_gateway_method_response.orders_batch_post_502.response_parameters
      },
      {
        status_code         = aws_api_gateway_integration_response.orders_batch_post_502.status_code
        selection_pattern   = aws_api_gateway_integration_response.orders_batch_post_502.selection_pattern
        response_templates  = aws_api_gateway_integration_response.orders_batch_post_502.response_templates
        response_parameters = aws_api_gateway_integration_response.orders_batch_post_502.response_parameters
      },
      {
        response_type       = aws_api_gateway_gateway_response.default_4xx.response_type
        response_parameters = aws_api_gateway_gateway_response.default_4xx.response_parameters
      },
      {
        response_type       = aws_api_gateway_gateway_response.default_5xx.response_type
        response_parameters = aws_api_gateway_gateway_response.default_5xx.response_parameters
      },
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "live"

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-api_gateway" })
}

output "api_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
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
    rate_limit  = 2000 # requisições/segundo (média)
    burst_limit = 400  # pico
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
  description  = "Orders request payload"
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

# ============================================================
# IAM Role para API
# ============================================================

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