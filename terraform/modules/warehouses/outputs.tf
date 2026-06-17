output "ui_wh_name" {
  value = snowflake_warehouse.ui.name
}

output "compute_wh_name" {
  value = snowflake_warehouse.compute.name
}

output "ml_wh_name" {
  value = snowflake_warehouse.ml.name
}

output "orchestration_wh_name" {
  value = snowflake_warehouse.orchestration.name
}

output "ingest_wh_name" {
  value = snowflake_warehouse.ingest.name
}
