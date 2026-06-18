# Foundation module: composes databases + warehouses and exposes their names
# to all downstream modules (rbac, security, app).

module "databases" {
  source      = "../databases"
  environment = var.environment
}

module "warehouses" {
  source                = "../warehouses"
  environment           = var.environment
  ui_wh_size            = var.ui_wh_size
  compute_wh_size       = var.compute_wh_size
  ml_wh_size            = var.ml_wh_size
  orchestration_wh_size = var.orchestration_wh_size
  ingest_wh_size        = var.ingest_wh_size
}
