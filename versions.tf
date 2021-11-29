terraform {
  experiments = [module_variable_optional_attrs]
  required_providers {
    metal = {
      source  = "equinix/metal"
      version = ">= 3.0.0"
    }
  }
}
