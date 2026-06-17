# ─── Masking Policies (PII) ───────────────────────────────────────────────────
# NEXUS_ADMIN vê dado real; demais roles recebem valor mascarado.

resource "snowflake_masking_policy" "email" {
  name     = "MASK_EMAIL"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara email — exibe domínio apenas para não-admins"

  signature {
    column {
      name = "val"
      type = "VARCHAR"
    }
  }

  masking_expression = <<-SQL
    CASE
      WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val
      ELSE REGEXP_REPLACE(val, '^[^@]+', '****')
    END
  SQL

  return_data_type = "VARCHAR"
}

resource "snowflake_masking_policy" "phone" {
  name     = "MASK_PHONE"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara telefone — exibe últimos 4 dígitos para não-admins"

  signature {
    column {
      name = "val"
      type = "VARCHAR"
    }
  }

  masking_expression = <<-SQL
    CASE
      WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val
      ELSE CONCAT('****-****-', RIGHT(REGEXP_REPLACE(val, '[^0-9]', ''), 4))
    END
  SQL

  return_data_type = "VARCHAR"
}

resource "snowflake_masking_policy" "pii_string" {
  name     = "MASK_PII_STRING"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara genérico para strings PII (nome, endereço, CPF, etc.)"

  signature {
    column {
      name = "val"
      type = "VARCHAR"
    }
  }

  masking_expression = <<-SQL
    CASE
      WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val
      ELSE '*** REDACTED ***'
    END
  SQL

  return_data_type = "VARCHAR"
}

resource "snowflake_masking_policy" "decimal_pii" {
  name     = "MASK_DECIMAL_PII"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Mascara valores decimais sensíveis (salário, ARR individual, etc.)"

  signature {
    column {
      name = "val"
      type = "DECIMAL(18,2)"
    }
  }

  masking_expression = <<-SQL
    CASE
      WHEN CURRENT_ROLE() IN ('${var.admin_role}') THEN val
      ELSE NULL
    END
  SQL

  return_data_type = "DECIMAL(18,2)"
}

# ─── Row Access Policy (multi-tenant org_id isolation) ────────────────────────

resource "snowflake_row_access_policy" "org_isolation" {
  name     = "RAP_ORG_ISOLATION"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Garante que cada org_id veja apenas seus próprios dados. NEXUS_ADMIN vê tudo."

  signature = {
    org_id = "VARCHAR"
  }

  row_access_expression = <<-SQL
    CURRENT_ROLE() IN ('${var.admin_role}', 'ACCOUNTADMIN')
    OR org_id = CURRENT_ACCOUNT()
    OR EXISTS (
        SELECT 1 FROM ${var.database_name}.CONFIG.ORG_USER_MAP
        WHERE org_id  = org_id
          AND user_name = CURRENT_USER()
    )
  SQL
}

# ─── Network Rules (zero egress policy) ──────────────────────────────────────
# Bloqueia egress externo; permite apenas endpoints internos Snowflake.

resource "snowflake_network_rule" "block_all_egress" {
  name     = "NEXUS_BLOCK_ALL_EGRESS"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Bloqueia todo tráfego de saída — zero egress policy"

  network_rule_type = "HOST_PORT"
  mode              = "EGRESS"
  value_list        = ["0.0.0.0:0-65535"]
}

resource "snowflake_network_rule" "allow_snowflake_services" {
  name     = "NEXUS_ALLOW_SNOWFLAKE_SERVICES"
  database = var.database_name
  schema   = "GOVERNANCE"
  comment  = "Permite comunicação com serviços internos Snowflake"

  network_rule_type = "SNOWFLAKE_VPC_ID"
  mode              = "INGRESS"
  value_list        = []
}
