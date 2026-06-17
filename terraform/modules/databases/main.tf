# ─── Databases ───────────────────────────────────────────────────────────────

resource "snowflake_database" "nexus_app" {
  name                        = "NEXUS_APP"
  data_retention_time_in_days = var.data_retention_app_days
  comment                     = "NEXUS AI DataOps — consumer database [${var.environment}]"
}

resource "snowflake_database" "nexus_provider" {
  name                        = "NEXUS_PROVIDER"
  data_retention_time_in_days = var.data_retention_app_days
  comment                     = "NEXUS AI DataOps — provider/package database [${var.environment}]"
}

# ─── Schemas: NEXUS_APP ───────────────────────────────────────────────────────

resource "snowflake_schema" "core" {
  database                    = snowflake_database.nexus_app.name
  name                        = "CORE"
  data_retention_time_in_days = var.data_retention_app_days
  comment                     = "Entidades consolidadas: Customer, Product, Transaction, Document"
}

resource "snowflake_schema" "raw" {
  database                    = snowflake_database.nexus_app.name
  name                        = "RAW"
  data_retention_time_in_days = var.data_retention_raw_days
  comment                     = "Dados brutos imutáveis de fontes externas"
}

resource "snowflake_schema" "std" {
  database                    = snowflake_database.nexus_app.name
  name                        = "STD"
  data_retention_time_in_days = var.data_retention_app_days
  comment                     = "Dados padronizados — outputs dbt staging"
}

resource "snowflake_schema" "mart" {
  database                    = snowflake_database.nexus_app.name
  name                        = "MART"
  data_retention_time_in_days = var.data_retention_app_days
  comment                     = "Marts de negócio — Dynamic Tables e dbt mart models"
}

resource "snowflake_schema" "ai" {
  database                    = snowflake_database.nexus_app.name
  name                        = "AI"
  data_retention_time_in_days = 30
  comment                     = "Outputs de IA: scores, embeddings, recomendações, sessões"
}

resource "snowflake_schema" "audit" {
  database                    = snowflake_database.nexus_app.name
  name                        = "AUDIT"
  data_retention_time_in_days = var.data_retention_audit_days
  comment                     = "Logs de auditoria: prompts, acessos, ações"
}

resource "snowflake_schema" "governance" {
  database                    = snowflake_database.nexus_app.name
  name                        = "GOVERNANCE"
  data_retention_time_in_days = 90
  comment                     = "Data Metric Functions e políticas de governança"
}

resource "snowflake_schema" "config" {
  database                    = snowflake_database.nexus_app.name
  name                        = "CONFIG"
  data_retention_time_in_days = 90
  comment                     = "Configurações do app: vertical packs, roles, thresholds"
}

# ─── Stages internos: NEXUS_APP.CORE ─────────────────────────────────────────

resource "snowflake_stage" "app_stage" {
  database = snowflake_database.nexus_app.name
  schema   = snowflake_schema.core.name
  name     = "APP_STAGE"
  comment  = "Arquivos da Streamlit app (pages, Home.py)"

  depends_on = [snowflake_schema.core]
}

resource "snowflake_stage" "ml_stage" {
  database = snowflake_database.nexus_app.name
  schema   = snowflake_schema.core.name
  name     = "ML_STAGE"
  comment  = "Modelos ML: churn_model.py e artefatos Snowpark"

  depends_on = [snowflake_schema.core]
}

resource "snowflake_stage" "semantic_stage" {
  database = snowflake_database.nexus_app.name
  schema   = snowflake_schema.core.name
  name     = "SEMANTIC_STAGE"
  comment  = "Semantic models YAML para Cortex Analyst"

  depends_on = [snowflake_schema.core]
}
