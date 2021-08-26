# VLAN management ##########################################
locals {
  vlan_meta = [
    for i in range(var.vlans_amount) : {
      vnid        = metal_vlan.mcc_vlan[i].vxlan
      subnet      = "192.168.${i + 1}.0"
      mask        = "255.255.255.0"
      router_addr = "192.168.${i + 1}.1"
      # choose first vlan as mgmt/regional scoped if seed node deployed
      mcc_regional = (i == 0) && var.deploy_seed ? true : false
    }
  ]
  seed_meta = {
    deploy      = var.deploy_seed
    addr        = cidrhost("${local.vlan_meta[0].subnet}/24", 2)
    public_addr = join("", metal_device.seed.*.access_public_ipv4)
    mask        = local.vlan_meta[0].mask
    vlan_id     = local.vlan_meta[0].vnid
    static_route = {
      subnet   = "192.168.0.0/16"
      next_hop = local.vlan_meta[0].router_addr
    }
  }
  router_meta = {
    public_addr = metal_device.edge.access_public_ipv4
  }
}

resource "metal_vlan" "mcc_vlan" {
  metro      = var.metro
  project_id = var.project_id

  count       = var.vlans_amount
  description = "mcc_${var.edge_hostname}_192.168.${count.index + 1}.0"
}

# VLAN management ##########################################

# Edge router #########################################

resource "metal_project_ssh_key" "ssh_key_object" {
  count = var.use_existing_ssh_key_name == "" ? 1 : 0

  name       = "mcc_infra_${var.edge_hostname}"
  public_key = file(abspath(var.ssh_public_key_path))
  project_id = var.project_id
}

# Get Project SSH Key by name
data "metal_project_ssh_key" "infra_ssh" {
  depends_on = [metal_project_ssh_key.ssh_key_object]

  search     = var.use_existing_ssh_key_name != "" ? var.use_existing_ssh_key_name : "mcc_infra_${var.edge_hostname}"
  project_id = var.project_id
}

resource "metal_device" "edge" {
  hostname            = "mcc-edge-router-${var.edge_hostname}"
  plan                = var.edge_size
  metro               = var.metro
  operating_system    = var.edge_os
  billing_cycle       = var.billing_cycle
  project_id          = var.project_id
  project_ssh_key_ids = [data.metal_project_ssh_key.infra_ssh.id]
}

# Change network mode to hybrid for the edge instance
resource "metal_device_network_type" "edge" {
  device_id = metal_device.edge.id
  type      = "hybrid"
}

# Attach vlans to the edge instance
resource "metal_port_vlan_attachment" "vlan_to_router" {
  depends_on = [metal_device.edge, metal_vlan.mcc_vlan]
  device_id  = metal_device_network_type.edge.id
  port_name  = "bond0"

  count     = var.vlans_amount
  vlan_vnid = metal_vlan.mcc_vlan[count.index].vxlan
}

# Seed node #########################################
resource "metal_device" "seed" {
  count = var.deploy_seed ? 1 : 0

  hostname            = "mcc-seed-${var.edge_hostname}"
  plan                = var.edge_size
  metro               = var.metro
  operating_system    = var.edge_os
  billing_cycle       = var.billing_cycle
  project_id          = var.project_id
  project_ssh_key_ids = [data.metal_project_ssh_key.infra_ssh.id]

  # keep only ipv4 addresses, skipping ipv6 management
  ip_address {
    type = "private_ipv4"
    cidr = 31
  }
  ip_address {
    type = "public_ipv4"
    cidr = 31
  }
}

# Change network mode to hybrid for the seed instance
resource "metal_device_network_type" "seed_network" {
  count = var.deploy_seed ? 1 : 0

  device_id = metal_device.seed[count.index].id
  # by default 'layer3' means hybrid-bonded
  type = "layer3"
}

# Attach mgmt vlan to the seed instance
resource "metal_port_vlan_attachment" "vlan_to_seed" {
  count = var.deploy_seed ? 1 : 0

  depends_on = [metal_device.seed, metal_vlan.mcc_vlan]
  device_id  = metal_device_network_type.seed_network[count.index].id
  port_name  = "bond0"
  # first vlan is mgmt related by default
  vlan_vnid = local.vlan_meta[0].vnid
}

resource "local_file" "ansible-inventory" {
  filename = "ansible-hosts-${var.edge_hostname}.ini"
  content  = <<EOT
[routers]
${metal_device.edge.access_public_ipv4}
[seed]
${join("", metal_device.seed.*.access_public_ipv4)}
[all:vars]
ansible_ssh_private_key_file = ${abspath(var.ssh_private_key_path)}
ansible_ssh_public_key_file  = ${abspath(var.ssh_public_key_path)}
ansible_user                 = root
ansible_ssh_common_args      = '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
EOT
}

resource "local_file" "network_config" {
  filename = "equinix_network_config.yaml"
  content  = <<EOT
${yamlencode({ "vlan" : local.vlan_meta, "seed" : local.seed_meta, "router" : local.router_meta, "metro" : var.metro })}
EOT
}
