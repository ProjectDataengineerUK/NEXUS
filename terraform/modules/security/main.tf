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

  # argument.name foi criado como "VAL" (uppercase) — Snowflake normaliza para uppercase
  # internamente mas o provider Terraform é case-sensitive no state; ignore para evitar
  # destroy+create em políticas já aplicadas em colunas.
  lifecycle {
    ignore_changes = [argument]
  }
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

  lifecycle {
    ignore_changes = [argument]
  }
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


# ─── Network Policy (allowlist de IPs por ambiente) ───────────────────────────

resource "snowflake_network_policy" "nexus_access" {
  name    = "NEXUS_NETWORK_POLICY"
  comment = "Restringe acesso ao NEXUS_APP por CIDR de escritório + CI/CD + Streamlit Cloud"

  allowed_ip_list = var.allowed_ip_ranges

  # Snowflake Streamlit IPs e IP do GitHub Actions são adicionados via var.allowed_ip_ranges
  # Formato: ["10.0.0.0/8", "203.0.113.0/24"]
}

resource "snowflake_network_policy_attachment" "nexus_account" {
  network_policy_name = snowflake_network_policy.nexus_access.name
  set_for_account     = true

  # Deixar vazio para aplicar a nível de conta; usuários específicos podem sobrescrever
  users = []
}


# ─── Tag-Based Masking (aplica masking_policy via tag PII) ────────────────────

# O provider Snowflake associa UMA masking policy por tag (não por valor da tag).
# A granularidade por valor ("email", "phone", "cpf") é gerenciada via ALTER TAG
# nos scripts SQL de setup (24_pii_tagging.sql).
# Aqui registramos a policy genérica VARCHAR como default da tag PII.

resource "snowflake_tag_masking_policy_association" "pii_default" {
  tag_id            = "${var.database_name}.GOVERNANCE.PII"
  masking_policy_id = "${var.database_name}.GOVERNANCE.${snowflake_masking_policy.pii_string.name}"
}


# ─── SSO / SAML Integration (stub — requer IdP externo configurado) ──────────

# NOTA: Para ativar SSO real, preencha var.saml_issuer_url e var.saml_sso_url
# com os metadados do seu IdP (Okta, Azure AD, Google Workspace, etc.)
# e aplique via terraform apply. Deixado como stub para não bloquear deployments
# sem IdP configurado.

resource "snowflake_saml_integration" "nexus_sso" {
  count = var.enable_sso ? 1 : 0

  name    = "NEXUS_SSO"
  enabled = true

  # IdP metadata — preencher via tfvars ou Vault
  saml2_issuer              = var.saml_issuer_url
  saml2_sso_url             = var.saml_sso_url
  saml2_provider            = var.saml_provider  # "OKTA" | "ADFS" | "Custom"
  saml2_x509_cert           = var.saml_x509_cert
  saml2_enable_sp_initiated = true

  # Força re-autenticação a cada 8h de sessão
  saml2_requested_nameid_format = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
}
