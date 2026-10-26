output "vmid" {
  value = proxmox_virtual_environment_vm.vm.id
}

output "target_node" {
  value = proxmox_virtual_environment_vm.vm.node_name
}

output "interface" {
  value = var.network_name
}

output "hostname" {
  value = proxmox_virtual_environment_vm.vm.name
}

output "vm_type" {
  value = "qemu"
}