variable "database_name" {
  description = "Nome do database principal (NEXUS_APP)"
  type        = string
}

variable "ui_wh_name" {
  description = "Nome do warehouse UI"
  type        = string
}

variable "compute_wh_name" {
  description = "Nome do warehouse COMPUTE"
  type        = string
}

variable "ml_wh_name" {
  description = "Nome do warehouse ML"
  type        = string
}

variable "orchestration_wh_name" {
  description = "Nome do warehouse ORCHESTRATION"
  type        = string
}

variable "ingest_wh_name" {
  description = "Nome do warehouse INGEST"
  type        = string
}
