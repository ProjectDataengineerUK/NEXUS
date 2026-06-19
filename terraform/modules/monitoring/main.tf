# NEXUS AI DataOps — Terraform: Monitoring Module (Sprint 2 P2)
# Resource monitors para crédito e alertas de warehouse

resource "snowflake_resource_monitor" "nexus_credit_monitor" {
  name         = "NEXUS_CREDIT_MONITOR"
  credit_quota = var.monthly_credit_quota

  frequency       = "MONTHLY"
  start_timestamp = "IMMEDIATELY"

  notify_triggers    = [75, 90]
  suspend_triggers   = [100]
  suspend_immediate_triggers = [110]

  notify_users = var.notify_users

  on_account = false
  warehouses = [
    var.app_warehouse_name,
  ]
}

resource "snowflake_resource_monitor" "nexus_ingest_monitor" {
  name         = "NEXUS_INGEST_CREDIT_MONITOR"
  credit_quota = var.ingest_credit_quota

  frequency       = "MONTHLY"
  start_timestamp = "IMMEDIATELY"

  notify_triggers          = [80]
  suspend_triggers         = [100]
  suspend_immediate_triggers = [120]

  notify_users = var.notify_users

  on_account = false
  warehouses = [
    var.ingest_warehouse_name,
  ]
}

# Task para verificar data freshness diariamente
resource "snowflake_task" "check_dt_freshness" {
  database  = var.database_name
  schema    = "AUDIT"
  name      = "CHECK_DT_FRESHNESS"
  warehouse = var.app_warehouse_name
  schedule  = "USING CRON 0 8 * * * UTC"
  enabled   = true

  sql_statement = <<-SQL
    INSERT INTO AUDIT.DATA_QUALITY_RESULTS
        (check_name, table_name, result, details, checked_at)
    SELECT
        'dt_freshness' AS check_name,
        t.table_name,
        CASE
            WHEN DATEDIFF('hour', t.data_timestamp, CURRENT_TIMESTAMP()) > 2 THEN 'FAIL'
            ELSE 'PASS'
        END AS result,
        'Lag: ' || DATEDIFF('minute', t.data_timestamp, CURRENT_TIMESTAMP()) || 'min' AS details,
        CURRENT_TIMESTAMP() AS checked_at
    FROM (
        SELECT 'DT_EXECUTIVE_KPIS' AS table_name, MAX(refreshed_at) AS data_timestamp FROM MART.DT_EXECUTIVE_KPIS
        UNION ALL
        SELECT 'DT_CUSTOMER_HEALTH', MAX(refreshed_at) FROM MART.DT_CUSTOMER_HEALTH
        UNION ALL
        SELECT 'DT_REVENUE_MOVEMENT', MAX(month) FROM MART.DT_REVENUE_MOVEMENT
    ) t
  SQL
}
