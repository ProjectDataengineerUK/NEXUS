output "package_name" {
  description = "Nome do Native App Package"
  value       = snowflake_application_package.nexus.name
}

output "app_stage_name" {
  description = "Nome do stage de artefatos do app"
  value       = snowflake_stage.app_stage.name
}

output "doc_stage_name" {
  description = "Nome do stage de documentos"
  value       = snowflake_stage.doc_stage.name
}

output "semantic_stage_name" {
  description = "Nome do stage de semantic models"
  value       = snowflake_stage.semantic_stage.name
}
