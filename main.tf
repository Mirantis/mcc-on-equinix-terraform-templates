# Configure the Equinix Metal Provider.
provider "metal" {
    max_retries = 3
    max_retry_wait_seconds = 30
}

# SSH Keys management ##########################################

# Create SSH Keys if they are not exist
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

# Routers management ##########################################

locals {
  # The first hardware reservation (if set) will always be selected for the router
  routers_custom_spec = {
    for i, m in var.metros :
      (m.metro) => {
        plan     = length(m.reserved_hardware != null ? m.reserved_hardware : []) > 0 ? m.reserved_hardware[0].plan : var.edge_size
        hardware_reservation_id = length(m.reserved_hardware != null ? m.reserved_hardware : []) > 0 ? m.reserved_hardware[0].id : ""
      }
  }
}

# Create routers in each configured metro
resource "metal_device" "edge" {
  count = length(local.routers_custom_spec)

  hostname                = "mcc-edge-router-${var.edge_hostname}"
  plan                    = local.routers_custom_spec[var.metros[count.index].metro].plan
  hardware_reservation_id = local.routers_custom_spec[var.metros[count.index].metro].hardware_reservation_id
  metro                   = var.metros[count.index].metro
  operating_system        = var.edge_os
  billing_cycle           = var.billing_cycle
  project_id              = var.project_id
  project_ssh_key_ids     = [data.metal_project_ssh_key.infra_ssh.id]
}

# Change network mode to hybrid for the edge instance
resource "metal_device_network_type" "edge" {
  count = length(metal_device.edge)

  device_id = metal_device.edge[count.index].id
  type      = "hybrid"
}

locals {
  routers_meta = {
    for i, m in var.metros :
    (m.metro) => {
      metro             = m.metro
      run_as_seed       = m.router_as_seed != null ? m.router_as_seed : false
      dhcp_addrs        = (m.routers_dhcp != null) ? m.routers_dhcp : []
      vlan_subnet       = "192.168.${i * 16}.0/20"
      vxlan_br_addr     = "192.168.255.${i + 1}"
      vxlan_subnet_mask = "255.255.255.0",
      private_addr      = metal_device.edge[i].access_private_ipv4,
      public_addr       = metal_device.edge[i].access_public_ipv4,
      device_id         = metal_device.edge[i].id
      port_id           = metal_device_network_type.edge[i].id
  } }
}

# VxLANs management ##########################################

locals {
  vxlans = {
    for i, mi in var.metros :
    (mi.metro) => [
      for j, mj in var.metros : {
        vnid          = (i > j) ? (j + 1) * 1000 + i + 1 : (i + 1) * 1000 + j + 1
        remote_addr   = local.routers_meta[var.metros[j].metro].private_addr
        next_hop      = local.routers_meta[var.metros[j].metro].vxlan_br_addr
        remote_subnet = local.routers_meta[var.metros[j].metro].vlan_subnet
      } if i != j
    ]
  }
}

output "vxlans" {
  value = local.vxlans
}

# VLANs management ##########################################

locals {
  vlans_by_metro = {
    for i, mi in var.metros :
    (mi.metro) => [
      for j in range(mi.vlans_amount) : {
        metro       = mi.metro
        subnet      = "192.168.${i * 16 + j}.0",
        mask        = "255.255.255.0",
        router_addr = "192.168.${i * 16 + j}.1",
        # choose first vlan as mgmt/regional scoped if seed node deployed or
        # or router should act like a seed node
        mcc_regional = (j == 0) && ((mi.deploy_seed == null ? false : mi.deploy_seed) ||
          (mi.router_as_seed == null ? false : mi.router_as_seed)) ? true : false
      }
  ] }

  vlans_list = flatten([
    for metro in local.vlans_by_metro : [
      for vlan in metro : {
        metro        = vlan.metro
        subnet       = vlan.subnet
        mask         = vlan.mask
        router_addr  = vlan.router_addr
        mcc_regional = vlan.mcc_regional
      }
  ]])

  vlans_map = {
    for vlan in local.vlans_list :
    (vlan.subnet) => {
      metro        = vlan.metro
      subnet       = vlan.subnet
      mask         = vlan.mask
      router_addr  = vlan.router_addr
      mcc_regional = vlan.mcc_regional
  } }
}

resource "metal_vlan" "mcc_vlan" {
  for_each = local.vlans_map

  metro       = each.value.metro
  description = "mcc_${var.edge_hostname}_${each.value.subnet}"
  project_id  = var.project_id
}

# Attach vlans to the edge instance
resource "metal_port_vlan_attachment" "vlan_to_router" {
  depends_on = [metal_device.edge, metal_vlan.mcc_vlan]
  for_each   = metal_vlan.mcc_vlan

  port_name = "bond0"
  device_id = local.routers_meta[each.value.metro].port_id
  vlan_vnid = each.value.vxlan
}

locals {
  vlans = {
    for m in var.metros :
    (m.metro) => [
      for subnet, vlan in metal_vlan.mcc_vlan : {
        metro        = vlan.metro
        vlan_id      = vlan.vxlan
        subnet       = subnet
        mask         = local.vlans_map[subnet].mask
        router_addr  = local.vlans_map[subnet].router_addr
        mcc_regional = local.vlans_map[subnet].mcc_regional
      } if m.metro == vlan.metro
  ] }
}

output "vlans" {
  value = local.vlans
}

# Seed nodes management ##########################################

locals {
  seed_nodes_meta = {
    for m in var.metros :
    (m.metro) => {
      addr                    = cidrhost("${local.vlans[m.metro][0].subnet}/24", 2)
      mask                    = local.vlans[m.metro][0].mask
      vlan_id                 = local.vlans[m.metro][0].vlan_id
      metro                   = m.metro
      plan                    = length(m.reserved_hardware != null ? m.reserved_hardware : []) > 1 ? m.reserved_hardware[1].plan : var.edge_size
      hardware_reservation_id = length(m.reserved_hardware != null ? m.reserved_hardware : []) > 1 ? m.reserved_hardware[1].id : ""
      static_route = {
        subnet   = "192.168.0.0/16"
        next_hop = local.vlans[m.metro][0].router_addr
      }
    } if m.deploy_seed == null ? false : m.deploy_seed
  }
}

resource "metal_device" "seed" {
  for_each = local.seed_nodes_meta

  hostname                = "mcc-seed-${var.edge_hostname}"
  plan                    = each.value["plan"]
  hardware_reservation_id = each.value["hardware_reservation_id"]
  metro                   = each.key
  operating_system        = var.edge_os
  billing_cycle           = var.billing_cycle
  project_id              = var.project_id
  project_ssh_key_ids     = [data.metal_project_ssh_key.infra_ssh.id]

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
  for_each = metal_device.seed

  device_id = each.value.id
  # by default 'layer3' means hybrid-bonded
  type = "layer3"
}

# Attach mgmt vlan to the seed instance
resource "metal_port_vlan_attachment" "vlan_to_seed" {
  for_each = metal_device.seed

  depends_on = [metal_device.seed, metal_vlan.mcc_vlan]
  device_id  = each.value.id
  port_name  = "bond0"
  # first vlan is mgmt related by default
  vlan_vnid = local.vlans[each.key][0].vlan_id
}

# Output management ##########################################

locals {
  routers = {
    for name, router in local.routers_meta :
    (router.public_addr) => {
      metro             = router.metro
      vxlan_br_addr     = router.vxlan_br_addr
      vxlan_subnet_mask = router.vxlan_subnet_mask
      private_addr      = router.private_addr
      public_addr       = router.public_addr
      run_as_seed       = router.run_as_seed
      dhcp_addrs        = router.dhcp_addrs
      vlans = [
        for vlan in local.vlans[name] : {
          vlan_id      = vlan.vlan_id
          router_addr  = vlan.router_addr
          mask         = vlan.mask
          subnet       = vlan.subnet
          mcc_regional = vlan.mcc_regional
      }]
      vxlans = [
        for vxlan in local.vxlans[name] : {
          vnid          = vxlan.vnid
          remote_addr   = vxlan.remote_addr
          next_hop      = vxlan.next_hop
          remote_subnet = vxlan.remote_subnet
      }]
  } }
}

locals {
  seed_nodes = merge({
  for device in metal_device.seed :
  (device.access_public_ipv4) => {
    metro        = local.seed_nodes_meta[device.metro].metro
    addr         = local.seed_nodes_meta[device.metro].addr
    mask         = local.seed_nodes_meta[device.metro].mask
    vlan_id      = local.seed_nodes_meta[device.metro].vlan_id
    static_route = local.seed_nodes_meta[device.metro].static_route
    public_addr  = device.access_public_ipv4
    is_router    = false
  } }, {
  for name, router in local.routers :
  (router.public_addr) => {
    metro        = router.metro
    addr         = router.vlans[0].router_addr
    mask         = router.vlans[0].mask
    vlan_id      = router.vlans[0].vlan_id
    static_route = {
      subnet   = join("/", [router.vlans[0].subnet, "24"])
      next_hop = router.vlans[0].router_addr
    }
    public_addr  = router.public_addr
    is_router    = true
  } if router.run_as_seed })
}

output "routers" {
  value = local.routers
}

output "seed_nodes" {
  value = local.seed_nodes
}

# Output management ##########################################

locals {
  inventory_file = "ansible-inventory.yaml"

  inventory_meta = {
    routers = {
      hosts = {
        for router in local.routers :
        (router.public_addr) => {
          dhcp_servers = router.dhcp_addrs
        }
      }
    }

    seed = {
      hosts = {
        for device in local.seed_nodes :
        (device.public_addr) => {
          is_router = device.is_router
        }
      }
    }

    all = {
      vars = {
        ansible_ssh_private_key_file = abspath(var.ssh_private_key_path)
        ansible_ssh_public_key_file  = abspath(var.ssh_public_key_path)
        ansible_user                 = "root"
        ansible_ssh_common_args      = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
      }
    }
  }
}

resource "local_file" "ansible-inventory" {
  filename = var.ansible_artifacts_dir != "" ? "${var.ansible_artifacts_dir}/${local.inventory_file}" : local.inventory_file
  content  = yamlencode(local.inventory_meta)
}
