# ─── Roles funcionais ─────────────────────────────────────────────────────────

resource "snowflake_account_role" "admin" {
  name    = "NEXUS_ADMIN"
  comment = "Administrador do NEXUS: acesso total, sem masking de PII"
}

resource "snowflake_account_role" "analyst" {
  name    = "NEXUS_ANALYST"
  comment = "Analista: acesso a marts e agentes, PII mascarado"
}

resource "snowflake_account_role" "viewer" {
  name    = "NEXUS_VIEWER"
  comment = "Visualizador: dashboards e chat, sem dados brutos"
}

resource "snowflake_account_role" "data_engineer" {
  name    = "NEXUS_DATA_ENGINEER"
  comment = "Engenheiro de dados: acesso a RAW, STD, pipelines e qualidade"
}

# ─── Hierarquia de roles ──────────────────────────────────────────────────────

resource "snowflake_grant_account_role" "viewer_to_analyst" {
  role_name        = snowflake_account_role.viewer.name
  parent_role_name = snowflake_account_role.analyst.name
}

resource "snowflake_grant_account_role" "analyst_to_admin" {
  role_name        = snowflake_account_role.analyst.name
  parent_role_name = snowflake_account_role.admin.name
}

resource "snowflake_grant_account_role" "admin_to_sysadmin" {
  role_name        = snowflake_account_role.admin.name
  parent_role_name = "SYSADMIN"
}

# ─── Grants de warehouse ──────────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_account_role" "viewer_ui_wh" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.ui_wh_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_compute_wh" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.compute_wh_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_ml_wh" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.ml_wh_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_ingest_wh" {
  account_role_name = snowflake_account_role.data_engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.ingest_wh_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_orch_wh" {
  account_role_name = snowflake_account_role.data_engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.orchestration_wh_name
  }
}

# ─── Grants de database ───────────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_account_role" "viewer_db" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_db" {
  account_role_name = snowflake_account_role.data_engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# ─── Grants de schema por role ────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_account_role" "viewer_schema_mart" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.MART"
  }
}

resource "snowflake_grant_privileges_to_account_role" "viewer_schema_ai" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.AI"
  }
}

resource "snowflake_grant_privileges_to_account_role" "viewer_schema_config" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.CONFIG"
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_schema_core" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.CORE"
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_schema_audit" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.AUDIT"
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_schema_governance" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${var.database_name}.GOVERNANCE"
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_schema_raw" {
  account_role_name = snowflake_account_role.data_engineer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE STAGE", "CREATE FILE FORMAT"]
  on_schema {
    schema_name = "${var.database_name}.RAW"
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_schema_std" {
  account_role_name = snowflake_account_role.data_engineer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE DYNAMIC TABLE"]
  on_schema {
    schema_name = "${var.database_name}.STD"
  }
}

# ─── Future grants automáticos ────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_account_role" "future_tables_mart_viewer" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.MART"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_tables_ai_viewer" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.AI"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_tables_core_analyst" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.CORE"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_tables_audit_analyst" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.AUDIT"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_dynamic_tables_mart" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "DYNAMIC TABLES"
      in_schema          = "${var.database_name}.MART"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_dynamic_tables_ai" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "DYNAMIC TABLES"
      in_schema          = "${var.database_name}.AI"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_tables_raw_engineer" {
  account_role_name = snowflake_account_role.data_engineer.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.RAW"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_tables_std_engineer" {
  account_role_name = snowflake_account_role.data_engineer.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${var.database_name}.STD"
    }
  }
}
