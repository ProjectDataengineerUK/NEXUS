variable "environment" {
  description = "Ambiente: dev | prod"
  type        = string
}

# Warehouse sizing overrides (optional — modules use defaults)
variable "ui_wh_size" {
  description = "Tamanho do warehouse UI"
  type        = string
  default     = "X-SMALL"
}

variable "compute_wh_size" {
  description = "Tamanho do warehouse COMPUTE"
  type        = string
  default     = "SMALL"
}

variable "ml_wh_size" {
  description = "Tamanho do warehouse ML"
  type        = string
  default     = "MEDIUM"
}

variable "orchestration_wh_size" {
  description = "Tamanho do warehouse ORCHESTRATION"
  type        = string
  default     = "X-SMALL"
}

variable "ingest_wh_size" {
  description = "Tamanho do warehouse INGEST"
  type        = string
  default     = "SMALL"
}
