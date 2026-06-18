output "database_name" {
  description = "Nome do banco de dados principal NEXUS_APP"
  value       = module.databases.nexus_app_name
}

output "provider_database_name" {
  description = "Nome do banco de dados do provider NEXUS_PROVIDER"
  value       = module.databases.nexus_provider_name
}

output "ui_wh_name" {
  description = "Nome do warehouse de UI"
  value       = module.warehouses.ui_wh_name
}

output "compute_wh_name" {
  description = "Nome do warehouse de COMPUTE"
  value       = module.warehouses.compute_wh_name
}

output "ml_wh_name" {
  description = "Nome do warehouse de ML"
  value       = module.warehouses.ml_wh_name
}

output "orchestration_wh_name" {
  description = "Nome do warehouse de ORCHESTRATION"
  value       = module.warehouses.orchestration_wh_name
}

output "ingest_wh_name" {
  description = "Nome do warehouse de INGEST"
  value       = module.warehouses.ingest_wh_name
}
