# ─── Masking Policies (PII) ───────────────────────────────────────────────────

resource "snowflake_masking_policy" "email" {
  name     = "MASK_EMAIL"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara email — exibe domínio apenas para não-admins"

  argument {
    name = "val"
    type = "VARCHAR"
  }

  body = "CASE WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val ELSE REGEXP_REPLACE(val, '^[^@]+', '****') END"

  return_data_type = "VARCHAR"
}

resource "snowflake_masking_policy" "phone" {
  name     = "MASK_PHONE"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara telefone — exibe últimos 4 dígitos para não-admins"

  argument {
    name = "val"
    type = "VARCHAR"
  }

  body = "CASE WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val ELSE CONCAT('****-****-', RIGHT(REGEXP_REPLACE(val, '[^0-9]', ''), 4)) END"

  return_data_type = "VARCHAR"
}

resource "snowflake_masking_policy" "pii_string" {
  name     = "MASK_PII_STRING"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara genérico para strings PII (nome, endereço, CPF, etc.)"

  argument {
    name = "val"
    type = "VARCHAR"
  }

  body = "CASE WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val ELSE '*** REDACTED ***' END"

  return_data_type = "VARCHAR"
}

resource "snowflake_masking_policy" "decimal_pii" {
  name     = "MASK_DECIMAL_PII"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara valores decimais sensíveis (salário, ARR individual, etc.)"

  argument {
    name = "val"
    type = "FLOAT"
  }

  body = "CASE WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val ELSE NULL END"

  return_data_type = "FLOAT"
}

# ─── Row Access Policy (multi-tenant org_id isolation) ────────────────────────

resource "snowflake_row_access_policy" "org_isolation" {
  name     = "RAP_ORG_ISOLATION"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Garante que cada org_id veja apenas seus próprios dados."

  argument {
    name = "org_id"
    type = "VARCHAR"
  }

  body = "CURRENT_ROLE() IN ('${var.admin_role}', 'ACCOUNTADMIN') OR org_id = CURRENT_ACCOUNT()"
}
