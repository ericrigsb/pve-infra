module "gitea" {
  source           = "./modules/lxc"
  node_name        = "pve3"
  lxc_id           = 103
  start_on_boot    = true
  init_hostname    = "gitea"
  os_template      = ""
  tags             = "imported;git;community-script"
  disk_size        = 32
  memory_dedicated = 1024
  memory_swap      = 1024
  network_interfaces = [
    {
      bridge      = "vmbr0"
      enabled     = true
      firewall    = false
      mac_address = "BC:24:11:DB:A5:C4"
      mtu         = 0
      name        = "eth0"
      rate_limit  = 0
      vlan_id     = 0
    }
  ]
  ip_configs = [
    {
      ipv4_address = "10.0.4.4/24"
      ipv4_gateway = "10.0.4.1"
    }
  ]
  nameservers = ["10.0.4.1"]
  startup_order = 40

  features = {
    keyctl  = true
    nesting = true
  }
}