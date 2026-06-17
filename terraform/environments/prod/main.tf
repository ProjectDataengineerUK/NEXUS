locals {
  environment = "prod"
}

module "databases" {
  source = "../../modules/databases"

  environment               = local.environment
  data_retention_app_days   = 7
  data_retention_raw_days   = 3
  data_retention_audit_days = 365
}

module "warehouses" {
  source = "../../modules/warehouses"

  environment = local.environment

  # Prod: tamanhos conforme workload real
  ui_wh_size            = "X-SMALL"
  compute_wh_size       = "SMALL"
  ml_wh_size            = "MEDIUM"
  orchestration_wh_size = "X-SMALL"
  ingest_wh_size        = "SMALL"

  # Auto-suspend balanceado para prod
  auto_suspend_ui_seconds          = 60
  auto_suspend_compute_seconds     = 120
  auto_suspend_ml_seconds          = 300
  auto_suspend_orch_seconds        = 60
  auto_suspend_ingest_seconds      = 120
}

module "rbac" {
  source = "../../modules/rbac"

  database_name         = module.databases.nexus_app_name
  ui_wh_name            = module.warehouses.ui_wh_name
  compute_wh_name       = module.warehouses.compute_wh_name
  ml_wh_name            = module.warehouses.ml_wh_name
  orchestration_wh_name = module.warehouses.orchestration_wh_name
  ingest_wh_name        = module.warehouses.ingest_wh_name

  depends_on = [module.databases, module.warehouses]
}

module "security" {
  source = "../../modules/security"

  database_name = module.databases.nexus_app_name
  admin_role    = module.rbac.role_admin

  depends_on = [module.databases, module.rbac]
}
