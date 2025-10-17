terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.80.0"
    }
  }
}

locals {
  base_tags = "lxc;terraform"
  full_tags = split(";", var.tags != "" ? "${local.base_tags};${var.tags}" : local.base_tags)
}

resource "proxmox_virtual_environment_container" "lxc" {
  node_name     = var.node_name
  start_on_boot = var.start_on_boot
  tags          = local.full_tags
  vm_id         = var.lxc_id
  unprivileged  = var.unprivileged

  console {
    enabled   = var.console_enabled
    tty_count = var.console_tty_count
    type      = var.console_type
  }

  cpu {
    architecture = var.cpu_arch
    cores        = var.cpu_cores
    units        = var.cpu_units
  }

  disk {
    datastore_id = var.disk_datastore_id
    size         = var.disk_size
  }

  initialization {
    hostname = var.init_hostname
  
    dynamic "dns" {
      for_each = length(var.nameservers) > 0 ? [1] : []
      content {
        servers = var.nameservers
      }
    }

    dynamic "ip_config" {
      for_each = var.ip_configs
      content {
        ipv4 {
          address = ip_config.value.ipv4_address
          gateway = ip_config.value.ipv4_gateway
        }
      }
    }
  }

  memory {
    dedicated = var.memory_dedicated
    swap      = var.memory_swap
  }

  dynamic "mount_point" {
    for_each = (var.mountpoint != null ? var.mountpoint : [])
    content {
      acl           = mount_point.value.mount_point_acl
      backup        = mount_point.value.mount_point_backup
      mount_options = mount_point.value.mount_point_options
      path          = mount_point.value.mount_point_path
      quota         = mount_point.value.mount_point_quota
      read_only     = mount_point.value.mount_point_read_only
      replicate     = mount_point.value.mount_point_replicate
      shared        = mount_point.value.mount_point_shared
      volume        = mount_point.value.mount_point_volume
    }
  }

  dynamic "device_passthrough" {
    for_each = (var.device_passthrough != null ? var.device_passthrough : [])
    content {
      deny_write = device_passthrough.value.deny_write
      gid        = device_passthrough.value.gid
      mode       = device_passthrough.value.mode
      path       = device_passthrough.value.path
      uid        = device_passthrough.value.uid
    }
  }

  dynamic "network_interface" {
    for_each = var.network_interfaces
    content {
      bridge      = network_interface.value.bridge
      enabled     = network_interface.value.enabled
      firewall    = network_interface.value.firewall
      mac_address = network_interface.value.mac_address
      mtu         = network_interface.value.mtu
      name        = network_interface.value.name
      rate_limit  = network_interface.value.rate_limit
      vlan_id     = network_interface.value.vlan_id
    }
  }

  operating_system {
    template_file_id = var.os_template
    type             = var.os_type
  }

  lifecycle {
    prevent_destroy = true
  }
}