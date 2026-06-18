variable "environment" {
  description = "Ambiente: dev | prod"
  type        = string
}

variable "database_name" {
  description = "Nome do banco de dados principal (NEXUS_APP)"
  type        = string
}

variable "app_version" {
  description = "Versão do Native App para o APPLICATION PACKAGE (ex: v1_0)"
  type        = string
  default     = "v1_0"
}

variable "admin_role" {
  description = "Role com acesso administrativo ao Native App"
  type        = string
  default     = "NEXUS_ADMIN"
}
