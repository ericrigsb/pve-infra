import {
  to = module.docker.proxmox_virtual_environment_vm.vm
  id = "pve0/100"
}

import {
  to = module.backup.proxmox_virtual_environment_container.lxc
  id = "pve0/101"
}

import {
  to = module.proxy.proxmox_virtual_environment_container.lxc
  id = "pve0/104"
}

import {
  to = module.pihole.proxmox_virtual_environment_container.lxc
  id = "pve0/102"
}

import {
  to = module.gitea.proxmox_virtual_environment_container.lxc
  id = "pve0/103"
}