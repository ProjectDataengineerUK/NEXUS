terraform {
  required_version = ">= 1.7"

  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.98"
    }
  }

  # Remote state — habilitar quando CI/CD estiver configurado
  # backend "s3" {
  #   bucket         = "nexus-terraform-state"
  #   key            = "snowflake/${var.environment}/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "nexus-terraform-lock"
  #   encrypt        = true
  # }
}

provider "snowflake" {
  # Autenticação via variáveis de ambiente (recomendado para CI/CD):
  #   SNOWFLAKE_ACCOUNT   = "<org>-<account>"
  #   SNOWFLAKE_USER      = "<user>"
  #   SNOWFLAKE_PASSWORD  = "<password>"   (ou SNOWFLAKE_PRIVATE_KEY_PATH)
  #
  # Para key-pair (produção):
  #   SNOWFLAKE_PRIVATE_KEY_PATH       = "/path/to/rsa_key.p8"
  #   SNOWFLAKE_PRIVATE_KEY_PASSPHRASE = "<passphrase>"

  role = var.snowflake_role
}
