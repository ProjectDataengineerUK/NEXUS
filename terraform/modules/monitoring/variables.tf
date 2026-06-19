variable "database_name" {
  description = "Nome do banco de dados NEXUS"
  type        = string
  default     = "NEXUS_APP"
}

variable "monthly_credit_quota" {
  description = "Cota mensal de créditos para o app warehouse"
  type        = number
  default     = 100
}

variable "ingest_credit_quota" {
  description = "Cota mensal de créditos para o ingest warehouse"
  type        = number
  default     = 50
}

variable "app_warehouse_name" {
  description = "Nome do warehouse principal da app"
  type        = string
  default     = "NEXUS_APP_WH"
}

variable "ingest_warehouse_name" {
  description = "Nome do warehouse de ingestão"
  type        = string
  default     = "NEXUS_INGEST_WH"
}

variable "notify_users" {
  description = "Lista de usuários a notificar ao atingir limites"
  type        = list(string)
  default     = []
}
