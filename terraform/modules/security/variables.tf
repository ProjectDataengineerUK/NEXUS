variable "database_name" {
  description = "Database onde as policies serão criadas"
  type        = string
}

variable "admin_role" {
  description = "Role que vê dados sem masking"
  type        = string
  default     = "NEXUS_ADMIN"
}

variable "allowed_ip_ranges" {
  description = "Lista de CIDRs permitidos pela network policy (escritório + CI/CD + Streamlit Cloud)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Aberto por padrão; substitua em produção
}

variable "enable_sso" {
  description = "Habilita o recurso snowflake_saml_integration (requer IdP externo configurado)"
  type        = bool
  default     = false
}

variable "saml_issuer_url" {
  description = "URL do issuer SAML do IdP (ex: https://app.okta.com/exk...)"
  type        = string
  default     = ""
}

variable "saml_sso_url" {
  description = "SSO URL do IdP"
  type        = string
  default     = ""
}

variable "saml_provider" {
  description = "Provedor SAML: OKTA | ADFS | Custom"
  type        = string
  default     = "Custom"
}

variable "saml_x509_cert" {
  description = "Certificado X.509 do IdP (base64, sem cabeçalhos BEGIN/END)"
  type        = string
  default     = ""
  sensitive   = true
}
