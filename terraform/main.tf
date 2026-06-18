module "foundation" {
  source      = "./modules/foundation"
  environment = var.environment
}

module "rbac" {
  source      = "./modules/rbac"
  environment = var.environment

  database_name         = module.foundation.database_name
  ui_wh_name            = module.foundation.ui_wh_name
  compute_wh_name       = module.foundation.compute_wh_name
  ml_wh_name            = module.foundation.ml_wh_name
  orchestration_wh_name = module.foundation.orchestration_wh_name
  ingest_wh_name        = module.foundation.ingest_wh_name

  providers = {
    snowflake               = snowflake.security_admin
    snowflake.account_admin = snowflake.account_admin
  }

  depends_on = [module.foundation]
}

module "security" {
  source        = "./modules/security"
  environment   = var.environment
  database_name = module.foundation.database_name

  providers = {
    snowflake = snowflake.security_admin
  }

  depends_on = [module.rbac]
}

module "app" {
  source        = "./modules/app"
  environment   = var.environment
  database_name = module.foundation.database_name
  app_version   = var.app_version

  providers = {
    snowflake               = snowflake
    snowflake.account_admin = snowflake.account_admin
  }

  depends_on = [module.security]
}
