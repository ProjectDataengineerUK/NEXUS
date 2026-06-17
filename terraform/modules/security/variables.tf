variable "database_name" {
  description = "Database onde as policies serão criadas"
  type        = string
}

variable "admin_role" {
  description = "Role que vê dados sem masking"
  type        = string
  default     = "NEXUS_ADMIN"
}
