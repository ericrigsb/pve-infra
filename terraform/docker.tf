module "docker" {
    source                = "./modules/vm"
    name                  = "docker"
    node_name             = "pve2"
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
    # Single scsi0 disk, values unchanged from the previous disk_* inputs
    # (local-lvm / scsi0 / iothread / replicate / 32). This guest is imported
    # and live, so the plan for module.docker MUST come back empty.
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        iothread     = true
        replicate    = true
        size         = 32
      }
    ]
    memory_dedicated      = 6144
    memory_floating       = 4096
    memory_keep_hugepages = false
    memory_shared         = 0
    network_devices = [
      { bridge = "vmbr0", firewall = true, model = "virtio" }
    ]
    os_type               = "l26"
    usb_mapping           = "usb-share"
    usb_usb3              = false
    network_name          = "ens18"
    startup_order = 30
}