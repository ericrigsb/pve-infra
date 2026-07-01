module "music" {
  source = "./modules/lxc"

  providers = {
    proxmox = proxmox.music
  }

  node_name         = "pve3"
  lxc_id            = 105
  start_on_boot     = true
  init_hostname     = "streamer"
  os_template       = ""
  tags              = "imported"
  disk_datastore_id = "local-lvm"
  disk_size         = 8
  memory_dedicated  = 256
  memory_swap       = 256
  unprivileged      = true

  device_passthrough = [
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/controlC0", uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/pcmC0D0c",  uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/pcmC0D0p",  uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/pcmC0D3p",  uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/pcmC0D7p",  uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/pcmC0D8p",  uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/seq",       uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/timer",     uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/hwC0D0",    uid = 0 },
    { deny_write = false, gid = 0, mode = "0660", path = "/dev/snd/hwC0D2",    uid = 0 }
  ]

  network_interfaces = [
    {
      bridge      = "vmbr0"
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

  nameservers   = ["10.0.4.1"]
  startup_order = 40

  features = {
    nesting = true
  }
}