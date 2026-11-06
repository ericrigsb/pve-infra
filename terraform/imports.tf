import {
  to = module.docker.proxmox_virtual_environment_vm.vm
  id = "pve2/100"
}

import {
  to = module.backup.proxmox_virtual_environment_container.lxc
  id = "pve2/101"
}

import {
  to = module.gitea.proxmox_virtual_environment_container.lxc
  id = "pve3/103"
}

import {
  to = module.music.proxmox_virtual_environment_container.lxc
  id = "pve3/105"
}

import {
  to = module.dns01.proxmox_virtual_environment_container.lxc
  id = "pve2/106"
}

import {
  to = module.dns02.proxmox_virtual_environment_container.lxc
  id = "pve3/107"
}

import {
  to = module.btbridge.proxmox_virtual_environment_container.lxc
  id = "pve2/108"
}
