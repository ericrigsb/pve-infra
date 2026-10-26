terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }
  }
}

locals {
  base_tags = "vm;terraform"
  full_tags = split(";", var.tags != "" ? "${local.base_tags};${var.tags}" : local.base_tags)
}

resource "proxmox_virtual_environment_vm" "vm" {
  name                = var.name
  node_name           = var.node_name
  machine             = var.machine
  bios                = var.bios
  migrate             = true
  on_boot             = var.on_boot
  reboot              = var.reboot
  reboot_after_update = var.reboot_after_update
  scsi_hardware       = var.scsi_hardware
  stop_on_destroy     = var.stop_on_destroy
  tags                = local.full_tags
  vm_id               = var.vm_id

  agent {
    enabled = var.agent_enabled
    timeout = var.agent_timeout
    trim    = var.agent_trim
  }

  cpu {
    cores      = var.cpu_cores
    flags      = var.cpu_flags
    hotplugged = var.cpu_hotplugged
    limit      = var.cpu_limit
    numa       = var.cpu_numa
    sockets    = var.cpu_sockets
    type       = var.cpu_type
    units      = var.cpu_units
  }

  # Dynamic rather than a single literal block so a guest can declare more than
  # one disk. The HAOS guest needs two (EFI vars + system) and is the reason
  # this changed; only `docker` calls this module today and it declares one, so
  # the generated config for it is byte-for-byte what the literal block produced.
  dynamic "disk" {
    for_each = var.disks

    content {
      datastore_id = disk.value.datastore_id
      file_id      = disk.value.file_id
      import_from  = disk.value.import_from
      interface    = disk.value.interface
      iothread     = disk.value.iothread
      replicate    = disk.value.replicate
      size         = disk.value.size
    }
  }

  # Optional+computed upstream, so null does not mean "unset" here the way it
  # does for `machine` and `bios` — it means "provider decides", and the
  # provider reads the order back from PVE. `docker` therefore keeps whatever
  # order its guest already has rather than gaining one from this module.
  boot_order = var.boot_order

  # Dynamic and nullable so a guest can declare an EFI vars disk without every
  # other guest having to. `docker` does not, so no block is emitted for it.
  dynamic "efi_disk" {
    for_each = var.efi_disk == null ? [] : [var.efi_disk]

    content {
      datastore_id      = efi_disk.value.datastore_id
      pre_enrolled_keys = efi_disk.value.pre_enrolled_keys
      type              = efi_disk.value.type
    }
  }

  memory {
    dedicated      = var.memory_dedicated
    floating       = var.memory_floating
    keep_hugepages = var.memory_keep_hugepages
    shared         = var.memory_shared
  }

  dynamic "network_device" {
    for_each = var.network_devices
    content {
      bridge   = network_device.value.bridge
      firewall = network_device.value.firewall
      model    = network_device.value.model
    }
  }

  operating_system {
    type = var.os_type
  }

  usb {
    mapping = var.usb_mapping
    usb3    = var.usb_usb3
  }

  # The serial console. Without it a guest that fails to boot produces no
  # readable output at all — useful for HAOS, where the appliance has no shell
  # to log into and `ansible.sh` will never reach it. Up to 4 are permitted;
  # one (`socket`) is the practical case.
  dynamic "serial_device" {
    for_each = var.serial_devices

    content {
      device = serial_device.value.device
    }
  }

  startup {
    order      = var.startup_order
    up_delay   = var.startup_up_delay
    down_delay = var.startup_down_delay
  }

  lifecycle {
    prevent_destroy = true
  }
}