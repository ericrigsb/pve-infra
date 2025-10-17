output "control_plane_vms" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.talos_cp :
    name => {
      vmid        = vm.vm_id
      hostname    = vm.name
      target_node = vm.node_name
      interface   = vm.network_device[0].bridge
      ip          = try(vm.ipv4_addresses[0], null)
    }
  }
}

output "worker_vms" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.talos_worker :
    name => {
      vmid        = vm.vm_id
      hostname    = vm.name
      target_node = vm.node_name
      interface   = vm.network_device[0].bridge
      ip          = try(vm.ipv4_addresses[0], null)
    }
  }
}

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}