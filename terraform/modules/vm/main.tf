terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
  }
}

locals {
  base_tags = "vm;terraform"
  full_tags = split(";", var.tags != "" ? "${local.base_tags};${var.tags}" : local.base_tags)
}

resource "proxmox_virtual_environment_vm" "vm" {
  name             = var.name
  node_name        = var.node_name
  on_boot          = var.on_boot
  reboot           = var.reboot
  reboot_after_update = var.reboot_after_update
  scsi_hardware    = var.scsi_hardware
  stop_on_destroy  = var.stop_on_destroy
  tags             = local.full_tags
  vm_id            = var.vm_id

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

  disk {
    datastore_id = var.disk_datastore_id
    interface    = var.disk_interface
    iothread     = var.disk_iothread
    replicate    = var.disk_replicate
    size         = var.disk_size
  }

  memory {
    dedicated        = var.memory_dedicated
    floating         = var.memory_floating
    keep_hugepages   = var.memory_keep_hugepages
    shared           = var.memory_shared
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

  lifecycle {
    prevent_destroy = true
  }
}