output "vmid" {
  value = proxmox_virtual_environment_container.lxc.id
}

output "target_node" {
  value = proxmox_virtual_environment_container.lxc.node_name
}

output "interface" {
  value = proxmox_virtual_environment_container.lxc.network_interface[0].name
}

output "hostname" {
  value = proxmox_virtual_environment_container.lxc.initialization[0].hostname
}

output "vm_type" {
  value = "lxc"
}