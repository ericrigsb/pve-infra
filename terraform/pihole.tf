module "pihole" {
  source = "./modules/lxc"
  node_name         = "pve3"
  lxc_id            = 102
  start_on_boot     = true
  init_hostname     = "pihole"
  os_template       = ""
  tags              = "imported;adblock;community-script"
  disk_datastore_id = "local-lvm"
  disk_size         = 8
  memory_dedicated  = 512
  memory_swap       = 512
  network_interfaces = [
    {
      bridge      = "vmbr0"
      enabled     = true
      firewall    = false
      mac_address = "BC:24:11:80:3F:54"
      mtu         = 0
      name        = "eth0"
      rate_limit  = 0
      vlan_id     = 0
    }
  ]
  ip_configs = [
    {
      ipv4_address = "10.0.4.3/24"
      ipv4_gateway = "10.0.4.1"
    }
  ]
  nameservers = ["10.0.4.1"]
  startup_order = 11

  features = {
    keyctl  = true
    nesting = true
  }
}