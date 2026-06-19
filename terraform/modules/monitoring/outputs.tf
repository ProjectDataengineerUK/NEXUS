output "credit_monitor_name" {
  value       = snowflake_resource_monitor.nexus_credit_monitor.name
  description = "Nome do resource monitor de crédito principal"
}

output "ingest_monitor_name" {
  value       = snowflake_resource_monitor.nexus_ingest_monitor.name
  description = "Nome do resource monitor de crédito de ingestão"
}

output "freshness_task_name" {
  value       = snowflake_task.check_dt_freshness.name
  description = "Nome da task de verificação de freshness"
}
