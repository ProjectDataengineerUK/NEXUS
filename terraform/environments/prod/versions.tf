terraform {
  required_version = ">= 1.7"

  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.98"
    }
  }

  backend "gcs" {}
}

provider "snowflake" {
  role = var.snowflake_role
}
