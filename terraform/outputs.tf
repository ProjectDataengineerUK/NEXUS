output "database_name" {
  value = module.foundation.database_name
}

output "ui_warehouse" {
  value = module.foundation.ui_warehouse
}

output "compute_warehouse" {
  value = module.foundation.compute_warehouse
}

output "ml_warehouse" {
  value = module.foundation.ml_warehouse
}

output "app_package_name" {
  value = module.app.package_name
}

output "streamlit_url" {
  value       = module.app.streamlit_url
  description = "URL da Streamlit App no Snowflake"
}
