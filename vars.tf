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

variable "metros" {
  type = list(object({
    metro          = string
    vlans_amount   = number
    # TODO(eromanova): define defaults for deploy_seed and router_as_seed variables once terraform 1.3 available
    deploy_seed    = optional(bool)
    router_as_seed = optional(bool)
    routers_dhcp   = optional(list(string))
  }))

  description = <<EOT
example of object:
"metros": [
  {
    "metro": "fr",
    "vlans_amount": "2",
    "deploy_seed": true,
  },
  {
    "metro": "da",
    "vlans_amount": "1",
    "deploy_seed": false,
    # router_as_seed defines if the router should be deployed as a seed node.
    # `deploy_seed` and `router_as_seed` should not be enabled at once.
    "router_as_seed: true,
    # routers_dhcp field is optional and may be filled after MCC bootstrap
    "routers_dhcp": [
        "192.168.16.21",
        "192.168.16.22",
        "192.168.16.23"
    ]
  }
]
EOT

  validation {
    condition = alltrue([
      for o in var.metros : o.metro != "" && o.vlans_amount > 0 && o.vlans_amount < 16
    ])
    error_message = "Metro should be specified explicitly and vlans_amount >0 and <16."
  }

  # TODO(eromanova): uncomment validation once terraform 1.3 is available and defaults for deploy_seed and router_as_seed are set
  # validation {
    # condition = alltrue([
      # for o in var.metros : !(o.deploy_seed && o.router_as_seed)
    # ])
    # error_message = "Invalid Metro configuration: deploy_seed and router_as_seed should not be enabled at once. Choose only one option."
  # }

}

variable "edge_os" {
  type    = string
  default = "ubuntu_20_04"

  validation {
    condition     = var.edge_os == "ubuntu_20_04"
    error_message = "Current ifrastructure setup supports following OS: [ubuntu_20_04]."
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
    condition     = length(var.edge_hostname) > 3
    error_message = "Variable edge_hostname should be human readable and contain at least 4 characters."
  }
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
