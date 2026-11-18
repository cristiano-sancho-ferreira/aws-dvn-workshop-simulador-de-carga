variable "region" {
  description = "Região AWS de deploy"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente (prd, dev, hml)"
  type        = string
  default     = "dev"
}

variable "account_client" {
  description = "ID da conta AWS"
  type        = string
  default     = "999999999999"
}

variable "organization_name" {
  description = "Nome da organização"
  type        = string
  default     = "sancho"
}

variable "application_name" {
  description = "Nome da aplicação"
  type        = string
  default     = "dvn-workshop"
}

variable "common_tags" {
  description = "Tags padrão aplicadas a todos os recursos"
  type        = map(string)
  default = {
    ManagedBy  = "terraform"
    Owner      = "sancho.consultoria"
    aws-apn-id = "pc:kjgfjkadsfgskfdg"
  }
}
