module "proxy" {
    source                        = "./modules/lxc"
    node_name                     = "pve3"
    start_on_boot                 = true
    tags                          = ""
    lxc_id                        = 104
    unprivileged                  = true
    console_enabled               = true
    console_tty_count             = 2
    console_type                  = "tty"
    cpu_arch                      = "amd64"
    cpu_cores                     = 2
    cpu_units                     = 1024
    disk_datastore_id             = "local-lvm"
    disk_size                     = 8
    init_hostname                 = "proxy"
    memory_dedicated              = 512
    memory_swap                   = 512
    mountpoint = []
    network_interfaces = [
      {
        bridge      = "vmbr0"
        enabled     = true
        firewall    = true
        mac_address = ""
        mtu         = 0
        name        = "eth0"
        rate_limit  = 0
        vlan_id     = 0
      },
      {
        bridge      = "vlan10"
        enabled     = true
        firewall    = true
        mac_address = ""
        mtu         = 0
        name        = "eth1"
        rate_limit  = 0
        vlan_id     = 0
      }
    ]
    ip_configs = [
      {
        ipv4_address = "10.0.4.200/24"
        ipv4_gateway = "10.0.4.1"
      },
      {
        ipv4_address = "192.168.187.11/24"
        ipv4_gateway = ""
      }
    ]
    nameservers = ["10.0.4.1"]
    os_template                   = ""
    os_type                       = "debian"
    startup_order = 10
}