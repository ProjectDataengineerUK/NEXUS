# ─── Warehouses NEXUS ────────────────────────────────────────────────────────
# Separados por workload para controle granular de créditos e isolamento.

resource "snowflake_warehouse" "ui" {
  name                = "NEXUS_UI_WH"
  warehouse_size      = var.ui_wh_size
  auto_suspend        = var.auto_suspend_ui_seconds
  auto_resume         = true
  initially_suspended = true
  comment             = "Streamlit UI e queries leves de usuário [${var.environment}]"

  # Evitar spill para o storage — queries de UI devem ser rápidas
  max_cluster_count = 1
  min_cluster_count = 1
  scaling_policy    = "STANDARD"
}

resource "snowflake_warehouse" "compute" {
  name                = "NEXUS_COMPUTE_WH"
  warehouse_size      = var.compute_wh_size
  auto_suspend        = var.auto_suspend_compute_seconds
  auto_resume         = true
  initially_suspended = true
  comment             = "Cortex Agents, Cortex Analyst, queries de marts [${var.environment}]"

  max_cluster_count = 2
  min_cluster_count = 1
  scaling_policy    = "ECONOMY"
}

resource "snowflake_warehouse" "ml" {
  name                = "NEXUS_ML_WH"
  warehouse_size      = var.ml_wh_size
  auto_suspend        = var.auto_suspend_ml_seconds
  auto_resume         = true
  initially_suspended = true
  comment             = "Treino e inference de modelos Snowpark ML [${var.environment}]"

  max_cluster_count = 1
  min_cluster_count = 1
  scaling_policy    = "STANDARD"
}

resource "snowflake_warehouse" "orchestration" {
  name                = "NEXUS_ORCHESTRATION_WH"
  warehouse_size      = var.orchestration_wh_size
  auto_suspend        = var.auto_suspend_orch_seconds
  auto_resume         = true
  initially_suspended = true
  comment             = "Tasks: audit log, data quality, embeddings, briefing [${var.environment}]"

  max_cluster_count = 1
  min_cluster_count = 1
  scaling_policy    = "STANDARD"
}

resource "snowflake_warehouse" "ingest" {
  name                = "NEXUS_INGEST_WH"
  warehouse_size      = var.ingest_wh_size
  auto_suspend        = var.auto_suspend_ingest_seconds
  auto_resume         = true
  initially_suspended = true
  comment             = "Pipelines de ingestão: COPY INTO, dbt run, embeddings [${var.environment}]"

  max_cluster_count = 2
  min_cluster_count = 1
  scaling_policy    = "ECONOMY"
}
