import {
  to = module.docker.proxmox_virtual_environment_vm.vm
  id = "pve2/100"
}

import {
  to = module.backup.proxmox_virtual_environment_container.lxc
  id = "pve2/101"
}

import {
  to = module.proxy.proxmox_virtual_environment_container.lxc
  id = "pve3/104"
}

import {
  to = module.pihole.proxmox_virtual_environment_container.lxc
  id = "pve3/102"
}

import {
  to = module.gitea.proxmox_virtual_environment_container.lxc
  id = "pve3/103"
}

import {
  to = module.music.proxmox_virtual_environment_container.lxc
  id = "pve3/105"
}