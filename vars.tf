# Project configuration
# required to export METAL_AUTH_TOKEN=XXXX

variable "project_id" {
  type        = string
  description = <<EOT
ID of your Project in Equinix Metal,
possible to handle as environment variable:
export TF_VAR_project_id="XXXXXXXXXXX"
EOT
}

# Machines configuration
variable "edge_size" {
  default = "c3.small.x86"
  type    = string
}

variable "metro" {
  type = string

  validation {
    condition     = var.metro != ""
    error_message = "Metro should be specified explicitly."
  }
}

variable "edge_os" {
  type    = string
  default = "ubuntu_18_04"

  validation {
    condition     = var.edge_os == "ubuntu_18_04"
    error_message = "Current ifrastructure setup supports following OS: [ubuntu_18_04]."
  }
}

variable "billing_cycle" {
  default = "hourly"
  type    = string
}

# SSH access configuration
variable "ssh_private_key_path" {
  type        = string
  default     = "ssh_key"
  description = <<EOT
Absolute path to the private part of SSH key
that will be deployed at Edge router and seed node devices
EOT
}

variable "ssh_public_key_path" {
  type        = string
  default     = "ssh_key.pub"
  description = <<EOT
Absolute path to the public part of SSH key
that will be deployed at Edge router and seed node devices
EOT
}

variable "use_existing_ssh_key_name" {
  type        = string
  default     = ""
  description = <<EOT
(Optional) Specify already created Equnix project SSH key
Edge router and seed node will be deployed with such key
ssh_private_key_path and ssh_public_key_path variables
should match the data stored in this key object
EOT
}

# MCC setup configuration
variable "edge_hostname" {
  type = string

  validation {
    condition     = length(var.edge_hostname) > 4
    error_message = "Variable edge_hostname should be human readable and contain at least 4 characters."
  }
}

variable "vlans_amount" {
  type        = number
  description = <<EOT
Desired amount of created VLAN's for MCC installations
EOT

  validation {
    condition     = var.vlans_amount > 0
    error_message = "Value of vlans_amount should be more than 0."
  }
}

variable "deploy_seed" {
  type        = bool
  default     = true
  description = <<EOT
If true, one of created VLAN's will
be choosed as mgmt/regional scoped
and seed node instance will be deployed
in that VLAN.
EOT
}

# Artifacts configuration
variable "ansible_artifacts_dir" {
  type        = string
  default     = ""
  description = <<EOT
If not empty, host and network configuration files,
generated for ansible playbook,
will be stored under desired directory
EOT
}
