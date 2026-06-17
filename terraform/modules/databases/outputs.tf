output "nexus_app_name" {
  value = snowflake_database.nexus_app.name
}

output "nexus_provider_name" {
  value = snowflake_database.nexus_provider.name
}

output "schema_core" {
  value = snowflake_schema.core.name
}

output "schema_raw" {
  value = snowflake_schema.raw.name
}

output "schema_std" {
  value = snowflake_schema.std.name
}

output "schema_mart" {
  value = snowflake_schema.mart.name
}

output "schema_ai" {
  value = snowflake_schema.ai.name
}

output "schema_audit" {
  value = snowflake_schema.audit.name
}

output "schema_governance" {
  value = snowflake_schema.governance.name
}

output "schema_config" {
  value = snowflake_schema.config.name
}
