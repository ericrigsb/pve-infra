module "backup" {
    source                      = "./modules/lxc"
    node_name                   = "pve2"
    start_on_boot               = true
    tags                        = "imported;manual"
    lxc_id                      = 101
    unprivileged                = false
    console_enabled             = true
    console_tty_count           = 2
    console_type                = "tty"
    cpu_arch                    = "amd64"
    cpu_cores                   = 2
    cpu_units                   = 1024
    disk_datastore_id           = "local-lvm"
    disk_size                   = 8
    init_hostname               = "backup"
    memory_dedicated            = 512
    memory_swap                 = 512
    mountpoint = [
        {
            mount_point_acl       = false
            mount_point_backup    = false
            mount_point_options   = []
            mount_point_path      = "/mnt/backup"
            mount_point_quota     = false
            mount_point_read_only = false
            mount_point_replicate = true
            mount_point_shared    = false
            mount_point_volume    = "/mnt/backup"
        }
    ]
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
      }
    ]
    ip_configs = [
      {
        ipv4_address = "10.0.4.8/24"
        ipv4_gateway = "10.0.4.1"
      }
    ]
    nameservers = ["10.0.4.1"]
    os_template                   = ""
    os_type                       = "debian"
    startup_order = 20

    features = {
      mount   = ["nfs"]
      nesting = true
    }
}