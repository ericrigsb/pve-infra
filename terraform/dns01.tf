module dns01 {
  source           = "./modules/lxc"
  node_name        = "pve2"
  lxc_id           = 106
  start_on_boot    = true
  init_hostname    = "dns01"
  os_template      = ""
  tags             = "adblock;imported;dns;community-script"
  disk_size        = 2
  memory_dedicated = 512
  memory_swap      = 512
  network_interfaces = [
    {
      bridge      = "vmbr0"
      enabled     = true
      firewall    = false
      mac_address = "BC:24:11:D3:3A:5B"
      mtu         = 0
      name        = "eth0"
      rate_limit  = 0
      vlan_id     = 0
    }
  ]
  ip_configs = [
    {
      ipv4_address = "10.0.4.5/24"
      ipv4_gateway = "10.0.4.1"
    }
  ]
  nameservers = ["10.0.4.5","10.0.4.3","10.0.4.1"]
  startup_order = 11

  features = {
    keyctl  = true
    nesting = true
  }
}