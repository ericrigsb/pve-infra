terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0-alpha.0"
    }
  }
}

locals {
  base_tags = "talos;terraform;vm"
  full_tags = split(";", var.tags != "" ? "${local.base_tags};${var.tags}" : local.base_tags)
}

resource "proxmox_virtual_environment_vm" "talos_cp" {
  for_each    = { for machine in var.talos_controlplane_config : machine.name => machine }
  name        = each.value.name
  node_name   = each.value.node
  vm_id       = each.value.id
  tags        = local.full_tags
  on_boot     = true

  cpu {
    cores = each.value.cpu_cores
    type  = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = false
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.network_device_vlan_id
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image[each.value.node].id
    file_format  = "raw"
    interface    = "virtio0"
    size         = each.value.disk_size
  }

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 5.X.
  }

  initialization {
    datastore_id = "local-lvm"
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.default_gateway
      }
    }
    dns {
        servers = var.dns_servers
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  for_each    = { for machine in var.talos_worker_config : machine.name => machine }
  depends_on  = [proxmox_virtual_environment_vm.talos_cp]
  name        = each.value.name
  node_name   = each.value.node
  vm_id       = each.value.id
  tags        = local.full_tags
  on_boot     = true

  cpu {
    cores = each.value.cpu_cores
    type  = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = false
  }

  network_device {
    bridge = var.network_bridge
    vlan_id = var.network_device_vlan_id
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image[each.value.node].id
    file_format  = "raw"
    interface    = "virtio0"
    size         = each.value.disk_size
  }

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 5.X.
  }

  initialization {
    datastore_id = "local-lvm"
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.default_gateway
      }
    }
    dns {
        servers = var.dns_servers
    }
  }
}