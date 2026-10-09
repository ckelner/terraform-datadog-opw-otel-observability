terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 4.21.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 3.0.0"
    }
  }
}
