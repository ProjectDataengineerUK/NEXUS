output "role_admin" {
  value = snowflake_role.admin.name
}

output "role_analyst" {
  value = snowflake_role.analyst.name
}

output "role_viewer" {
  value = snowflake_role.viewer.name
}

output "role_data_engineer" {
  value = snowflake_role.data_engineer.name
}
