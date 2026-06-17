output "role_admin" {
  value = snowflake_account_role.admin.name
}

output "role_analyst" {
  value = snowflake_account_role.analyst.name
}

output "role_viewer" {
  value = snowflake_account_role.viewer.name
}

output "role_data_engineer" {
  value = snowflake_account_role.data_engineer.name
}
