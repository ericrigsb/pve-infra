module "btbridge" {
  source = "./modules/lxc"

  providers = {
    proxmox = proxmox.music
  }

  # pve2 hosts the Intel 8265/8275 CNVi wireless card; pve3 is wired-only
  # (I219-LM) and has no Bluetooth radio. bluetoothd runs on this host and is
  # exposed to the container over the bind-mounted D-Bus socket.
  node_name         = "pve2"
  lxc_id            = 108
  start_on_boot     = true
  init_hostname     = "btbridge"
  os_template       = ""
  tags              = "imported;bluetooth;sendspin"
  disk_datastore_id = "local-lvm"
  disk_size         = 8
  memory_dedicated  = 768
  memory_swap       = 768
  # Privileged + AppArmor unconfined are required: the container reaches the
  # host's bluetoothd over a bind-mounted D-Bus socket, which needs access to
  # the BlueZ management socket. See deployment/lxc/README.md upstream.
  unprivileged = false

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
      ipv4_address = "10.0.4.20/24"
      ipv4_gateway = "10.0.4.1"
    }
  ]

  nameservers   = ["10.0.4.5", "10.0.4.3", "10.0.4.1"]
  os_type       = "ubuntu"
  startup_order = 40

  features = {
    nesting = true
  }
}
