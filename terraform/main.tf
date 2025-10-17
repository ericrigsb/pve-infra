module "docker" {
    source                = "./modules/vm"
    name                  = "docker"
    node_name             = "pve0"
    on_boot               = true
    reboot                = false
    reboot_after_update   = false
    scsi_hardware         = "virtio-scsi-single"
    stop_on_destroy       = true
    tags                  = "imported;manual"
    vm_id                 = 100
    agent_enabled         = true
    agent_timeout         = "15m"
    agent_trim            = false
    cpu_cores             = 2
    cpu_flags             = []
    cpu_hotplugged        = 0
    cpu_limit             = 0
    cpu_numa              = false
    cpu_sockets           = 1
    cpu_type              = "host"
    cpu_units             = 1024
    disk_datastore_id     = "local-lvm"
    disk_interface        = "scsi0"
    disk_iothread         = true
    disk_replicate        = true
    disk_size             = 32
    memory_dedicated      = 4096
    memory_floating       = 2048
    memory_keep_hugepages = false
    memory_shared         = 0
    network_devices = [
      { bridge = "vlan200", firewall = true, model = "virtio" }
    ]
    os_type               = "l26"
    usb_mapping           = "usb-share"
    usb_usb3              = false
    network_name          = "ens18"
}

module "backup" {
    source                      = "./modules/lxc"
    node_name                   = "pve0"
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
        bridge      = "vlan200"
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
}

module "proxy" {
    source                        = "./modules/lxc"
    node_name                     = "pve0"
    start_on_boot                 = true
    tags                          = ""
    lxc_id                        = 104
    unprivileged                  = true
    console_enabled               = true
    console_tty_count             = 2
    console_type                  = "tty"
    cpu_arch                      = "amd64"
    cpu_cores                     = 4
    cpu_units                     = 1024
    disk_datastore_id             = "local-lvm"
    disk_size                     = 8
    init_hostname                 = "proxy"
    memory_dedicated              = 512
    memory_swap                   = 512
    mountpoint = []
    network_interfaces = [
      {
        bridge      = "vlan200"
        enabled     = true
        firewall    = true
        mac_address = ""
        mtu         = 0
        name        = "eth0"
        rate_limit  = 0
        vlan_id     = 0
      },
      {
        bridge      = "vmbr0"
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
}

module "pihole" {
  source = "./modules/lxc"
  node_name         = "pve0"
  lxc_id            = 102
  start_on_boot     = true
  init_hostname     = "pihole"
  os_template       = ""
  tags              = "imported;adblock;community-script"
  disk_datastore_id = "local-lvm"
  disk_size         = 2
  network_interfaces = [
    {
      bridge      = "vlan200"
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
}

module "gitea" {
  source           = "./modules/lxc"
  node_name        = "pve0"
  lxc_id           = 103
  start_on_boot    = true
  init_hostname    = "gitea"
  os_template      = ""
  tags             = "imported;git;community-script"
  network_interfaces = [
    {
      bridge      = "vlan200"
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
  memory_dedicated = 1024
}

module "music" {
  source           = "./modules/lxc"
  node_name        = "pve0"
  lxc_id           = 105
  start_on_boot    = true
  init_hostname    = "music"
  os_template      = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  tags             = ""
  disk_datastore_id = "local-lvm"
  disk_size        = 8
  memory_dedicated = 256
  memory_swap      = 256
  device_passthrough = [
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/controlC0"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/pcmC0D0c"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/pcmC0D0p"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/pcmC0D1p"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/pcmC0D3p"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/pcmC0D7p"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/pcmC0D8p"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/seq"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/timer"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/hwC0D0"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/hwC0D3"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/hwC0D4"
      uid        = 0
    },
    {
      deny_write = false
      gid        = 0
      mode       = "0660"
      path       = "/dev/snd/hwC0D5"
      uid        = 0
    }
  ]
  network_interfaces = [
    {
      bridge      = "vlan200"
      enabled     = true
      firewall    = false
      mac_address = ""
      mtu         = 0
      name        = "eth0"
      rate_limit  = 0
      vlan_id     = 0
    }
  ]
  ip_configs = [
    {
      ipv4_address = "10.0.4.19/24"
      ipv4_gateway = "10.0.4.1"
    }
  ]
  nameservers = ["10.0.4.1"]
}

module "talos_cluster" {
  source                 = "./modules/talos"
  cluster_name           = "redcloud"
  talos_version          = "1.10.4"
  network_bridge         = "vlan200"
  network_device_vlan_id = null
  default_gateway        = "10.0.4.1"
  dns_servers            = [ "10.0.4.1" ]
  proxmox_nodes          = [ "pve1", "pve2" ]
  talos_controlplane_config = [{
    id              = 201
    name            = "talos-cp-01"
    ip              = "10.0.4.2"
    node            = "pve1"
    cpu_cores       = 4
    cpu_type        = "host"
    memory          = 3072
    disk_size       = 10
  },{
    id              = 202
    name            = "talos-cp-02"
    ip              = "10.0.4.6"
    node            = "pve2"
    cpu_cores       = 4
    cpu_type        = "host"
    memory          = 7168
    disk_size       = 32
  }]
  talos_worker_config = [{
    id        = 211
    name      = "talos-worker-01"
    ip        = "10.0.4.11"
    node      = "pve1"
    cpu_cores = 4
    cpu_type  = "host"
    memory    = 6144
    disk_size = 32
  },{
    id        = 212
    name      = "talos-worker-02"
    ip        = "10.0.4.12"
    node      = "pve1"
    cpu_cores = 4
    cpu_type  = "host"
    memory    = 6144
    disk_size = 32
  }]
}