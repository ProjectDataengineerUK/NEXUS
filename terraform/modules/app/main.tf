# ─── Native App Package ───────────────────────────────────────────────────────

resource "snowflake_application_package" "nexus" {
  name    = "NEXUS_AI_DATAOPS_PKG"
  comment = "Package do NEXUS AI DataOps Native App [${var.environment}]"

  distribution = "INTERNAL"
}

# ─── Stages internos do package ──────────────────────────────────────────────
# Os stages ficam no database NEXUS_APP (consumer side) e são montados no
# manifest.yml. O CI faz PUT dos artefatos antes de REGISTER VERSION.

resource "snowflake_stage" "app_stage" {
  name     = "APP_STAGE"
  database = var.database_name
  schema   = "CORE"
  comment  = "Artefatos do Native App: Streamlit pages, handlers Python"
  url      = ""
  encryption {
    type = "SNOWFLAKE_SSE"
  }
}

resource "snowflake_stage" "doc_stage" {
  name     = "DOC_STAGE"
  database = var.database_name
  schema   = "CORE"
  comment  = "Documentos carregados pelos usuários para Document Intelligence"
  directory {
    enable = true
  }
  encryption {
    type = "SNOWFLAKE_SSE"
  }
}

resource "snowflake_stage" "semantic_stage" {
  name     = "SEMANTIC_STAGE"
  database = var.database_name
  schema   = "CORE"
  comment  = "Semantic models YAML para Cortex Analyst"
  url      = ""
  encryption {
    type = "SNOWFLAKE_SSE"
  }
}

resource "snowflake_stage" "cortex_search_stage" {
  name     = "CORTEX_SEARCH_STAGE"
  database = var.database_name
  schema   = "CORE"
  comment  = "Configurações de Cortex Search services"
  url      = ""
  encryption {
    type = "SNOWFLAKE_SSE"
  }
}

# ─── Grants de acesso aos stages ──────────────────────────────────────────────

resource "snowflake_grant_privileges_to_account_role" "admin_app_stage" {
  account_role_name = var.admin_role
  privileges        = ["READ", "WRITE"]
  on_schema_object {
    object_type = "STAGE"
    object_name = "${var.database_name}.CORE.${snowflake_stage.app_stage.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_doc_stage" {
  account_role_name = var.admin_role
  privileges        = ["READ", "WRITE"]
  on_schema_object {
    object_type = "STAGE"
    object_name = "${var.database_name}.CORE.${snowflake_stage.doc_stage.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_semantic_stage" {
  account_role_name = var.admin_role
  privileges        = ["READ", "WRITE"]
  on_schema_object {
    object_type = "STAGE"
    object_name = "${var.database_name}.CORE.${snowflake_stage.semantic_stage.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_pkg" {
  account_role_name = var.admin_role
  privileges        = ["INSTALL", "DEVELOP"]
  on_account_object {
    object_type = "APPLICATION PACKAGE"
    object_name = snowflake_application_package.nexus.name
  }
}
