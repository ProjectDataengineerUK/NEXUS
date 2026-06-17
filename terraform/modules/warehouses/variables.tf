variable "environment" {
  description = "Nome do ambiente (dev | prod)"
  type        = string
}

# Tamanhos por ambiente — dev usa XS para tudo, prod usa tamanhos corretos
variable "ui_wh_size" {
  description = "Tamanho do warehouse UI (Streamlit + queries leves)"
  type        = string
  default     = "X-SMALL"
}

variable "compute_wh_size" {
  description = "Tamanho do warehouse COMPUTE (Cortex, marts, analytics)"
  type        = string
  default     = "SMALL"
}

variable "ml_wh_size" {
  description = "Tamanho do warehouse ML (Snowpark ML, treino e inference)"
  type        = string
  default     = "MEDIUM"
}

variable "orchestration_wh_size" {
  description = "Tamanho do warehouse ORCHESTRATION (Tasks, audit, embeddings)"
  type        = string
  default     = "X-SMALL"
}

variable "ingest_wh_size" {
  description = "Tamanho do warehouse INGEST (COPY INTO, dbt, pipelines)"
  type        = string
  default     = "SMALL"
}

variable "auto_suspend_ui_seconds" {
  description = "Auto-suspend em segundos para UI warehouse"
  type        = number
  default     = 60
}

variable "auto_suspend_compute_seconds" {
  description = "Auto-suspend em segundos para COMPUTE warehouse"
  type        = number
  default     = 120
}

variable "auto_suspend_ml_seconds" {
  description = "Auto-suspend em segundos para ML warehouse (jobs longos)"
  type        = number
  default     = 300
}

variable "auto_suspend_orch_seconds" {
  description = "Auto-suspend em segundos para ORCHESTRATION warehouse"
  type        = number
  default     = 60
}

variable "auto_suspend_ingest_seconds" {
  description = "Auto-suspend em segundos para INGEST warehouse"
  type        = number
  default     = 120
}
