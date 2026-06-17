# ─── Roles funcionais ─────────────────────────────────────────────────────────

resource "snowflake_role" "admin" {
  name    = "NEXUS_ADMIN"
  comment = "Administrador do NEXUS: acesso total, sem masking de PII"
}

resource "snowflake_role" "analyst" {
  name    = "NEXUS_ANALYST"
  comment = "Analista: acesso a marts e agentes, PII mascarado"
}

resource "snowflake_role" "viewer" {
  name    = "NEXUS_VIEWER"
  comment = "Visualizador: dashboards e chat, sem dados brutos"
}

resource "snowflake_role" "data_engineer" {
  name    = "NEXUS_DATA_ENGINEER"
  comment = "Engenheiro de dados: acesso a RAW, STD, pipelines e qualidade"
}

# ─── Hierarquia de roles ──────────────────────────────────────────────────────
# VIEWER ⊆ ANALYST ⊆ ADMIN ⊆ SYSADMIN

resource "snowflake_grant_account_role" "viewer_to_analyst" {
  role_name        = snowflake_role.viewer.name
  parent_role_name = snowflake_role.analyst.name
}

resource "snowflake_grant_account_role" "analyst_to_admin" {
  role_name        = snowflake_role.analyst.name
  parent_role_name = snowflake_role.admin.name
}

resource "snowflake_grant_account_role" "admin_to_sysadmin" {
  role_name        = snowflake_role.admin.name
  parent_role_name = "SYSADMIN"
}

# ─── Grants de warehouse ──────────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_role" "viewer_ui_wh" {
  role_name  = snowflake_role.viewer.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.ui_wh_name
  }
}

resource "snowflake_grant_privileges_to_role" "analyst_compute_wh" {
  role_name  = snowflake_role.analyst.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.compute_wh_name
  }
}

resource "snowflake_grant_privileges_to_role" "admin_ml_wh" {
  role_name  = snowflake_role.admin.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.ml_wh_name
  }
}

resource "snowflake_grant_privileges_to_role" "engineer_ingest_wh" {
  role_name  = snowflake_role.data_engineer.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.ingest_wh_name
  }
}

resource "snowflake_grant_privileges_to_role" "engineer_orch_wh" {
  role_name  = snowflake_role.data_engineer.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.orchestration_wh_name
  }
}

# ─── Grants de database ───────────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_role" "viewer_db" {
  role_name  = snowflake_role.viewer.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

resource "snowflake_grant_privileges_to_role" "engineer_db" {
  role_name  = snowflake_role.data_engineer.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# ─── Grants de schema por role ────────────────────────────────────────────────

# VIEWER: MART, AI, CONFIG (dashboards e chat)
resource "snowflake_grant_privileges_to_role" "viewer_schema_mart" {
  role_name  = snowflake_role.viewer.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.MART"
  }
}

resource "snowflake_grant_privileges_to_role" "viewer_schema_ai" {
  role_name  = snowflake_role.viewer.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.AI"
  }
}

resource "snowflake_grant_privileges_to_role" "viewer_schema_config" {
  role_name  = snowflake_role.viewer.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.CONFIG"
  }
}

# ANALYST: adiciona CORE, AUDIT, GOVERNANCE
resource "snowflake_grant_privileges_to_role" "analyst_schema_core" {
  role_name  = snowflake_role.analyst.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.CORE"
  }
}

resource "snowflake_grant_privileges_to_role" "analyst_schema_audit" {
  role_name  = snowflake_role.analyst.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.AUDIT"
  }
}

resource "snowflake_grant_privileges_to_role" "analyst_schema_governance" {
  role_name  = snowflake_role.analyst.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.GOVERNANCE"
  }
}

# DATA_ENGINEER: adiciona RAW, STD
resource "snowflake_grant_privileges_to_role" "engineer_schema_raw" {
  role_name  = snowflake_role.data_engineer.name
  privileges = ["USAGE", "CREATE TABLE", "CREATE STAGE", "CREATE FILE FORMAT"]
  on_schema {
    schema_name = "${var.database_name}.RAW"
  }
}

resource "snowflake_grant_privileges_to_role" "engineer_schema_std" {
  role_name  = snowflake_role.data_engineer.name
  privileges = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE DYNAMIC TABLE"]
  on_schema {
    schema_name = "${var.database_name}.STD"
  }
}

# ─── Future grants automáticos ────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_role" "future_tables_mart_viewer" {
  role_name  = snowflake_role.viewer.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.MART"
    }
  }
}

resource "snowflake_grant_privileges_to_role" "future_tables_ai_viewer" {
  role_name  = snowflake_role.viewer.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.AI"
    }
  }
}

resource "snowflake_grant_privileges_to_role" "future_tables_core_analyst" {
  role_name  = snowflake_role.analyst.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.CORE"
    }
  }
}

resource "snowflake_grant_privileges_to_role" "future_tables_audit_analyst" {
  role_name  = snowflake_role.analyst.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.AUDIT"
    }
  }
}

resource "snowflake_grant_privileges_to_role" "future_dynamic_tables_mart" {
  role_name  = snowflake_role.analyst.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "DYNAMIC TABLES"
      in_schema          = "${var.database_name}.MART"
    }
  }
}

resource "snowflake_grant_privileges_to_role" "future_dynamic_tables_ai" {
  role_name  = snowflake_role.analyst.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "DYNAMIC TABLES"
      in_schema          = "${var.database_name}.AI"
    }
  }
}

resource "snowflake_grant_privileges_to_role" "future_tables_raw_engineer" {
  role_name  = snowflake_role.data_engineer.name
  privileges = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.RAW"
    }
  }
}

resource "snowflake_grant_privileges_to_role" "future_tables_std_engineer" {
  role_name  = snowflake_role.data_engineer.name
  privileges = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.STD"
    }
  }
}
