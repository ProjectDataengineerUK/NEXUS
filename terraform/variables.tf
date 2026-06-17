variable "snowflake_account" {
  description = "Snowflake account name (sem org prefix)"
  type        = string
}

variable "snowflake_org" {
  description = "Snowflake organization name"
  type        = string
}

variable "snowflake_user" {
  description = "Usuário de deploy (NEXUS_DEPLOY_USER)"
  type        = string
}

variable "snowflake_password" {
  description = "Senha do usuário de deploy"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Ambiente: dev | prod"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment deve ser 'dev' ou 'prod'."
  }
}

variable "app_version" {
  description = "Versão do Native App (ex: v1_0)"
  type        = string
  default     = "v1_0"
}

variable "demo_org_id" {
  description = "Org ID para dados de demo"
  type        = string
  default     = "ORG-DEMO-001"
}
