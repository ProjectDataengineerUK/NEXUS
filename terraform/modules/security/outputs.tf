output "mask_email_name" {
  value = snowflake_masking_policy.email.name
}

output "mask_phone_name" {
  value = snowflake_masking_policy.phone.name
}

output "mask_pii_string_name" {
  value = snowflake_masking_policy.pii_string.name
}

output "mask_decimal_pii_name" {
  value = snowflake_masking_policy.decimal_pii.name
}

output "rap_org_isolation_name" {
  value = snowflake_row_access_policy.org_isolation.name
}
