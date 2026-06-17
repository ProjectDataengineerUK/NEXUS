variable "environment" {
  description = "Nome do ambiente (dev | prod)"
  type        = string
}

variable "data_retention_app_days" {
  description = "Time Travel para NEXUS_APP"
  type        = number
  default     = 7
}

variable "data_retention_raw_days" {
  description = "Time Travel para schema RAW (dados imutáveis)"
  type        = number
  default     = 3
}

variable "data_retention_audit_days" {
  description = "Time Travel para schema AUDIT"
  type        = number
  default     = 365
}
