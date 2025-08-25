output "vms" {
  sensitive = true
  value = concat(
    [
      {
        vmid          = module.docker.vmid
        hostname      = module.docker.hostname
        target_node   = module.docker.target_node
        interface     = module.docker.interface
        vm_type       = module.docker.vm_type
        public_key    = var.pve_infra_ssh_public_key
        root_password = var.guest_root_password
      },
      {
        vmid          = module.backup.vmid
        hostname      = module.backup.hostname
        target_node   = module.backup.target_node
        interface     = module.backup.interface
        vm_type       = module.backup.vm_type
        public_key    = var.pve_infra_ssh_public_key
        root_password = var.guest_root_password
      },
      {
        vmid          = module.proxy.vmid
        hostname      = module.proxy.hostname
        target_node   = module.proxy.target_node
        interface     = module.proxy.interface
        vm_type       = module.proxy.vm_type
        public_key    = var.pve_infra_ssh_public_key
        root_password = var.guest_root_password
      },
      {
        vmid          = module.pihole.vmid
        hostname      = module.pihole.hostname
        target_node   = module.pihole.target_node
        interface     = module.pihole.interface
        vm_type       = module.pihole.vm_type
        public_key    = var.pve_infra_ssh_public_key
        root_password = var.guest_root_password
      },
      {
        vmid          = module.gitea.vmid
        hostname      = module.gitea.hostname
        target_node   = module.gitea.target_node
        interface     = module.gitea.interface
        vm_type       = module.gitea.vm_type
        public_key    = var.pve_infra_ssh_public_key
        root_password = var.guest_root_password
      },
      {
        vmid          = module.music.vmid
        hostname      = module.music.hostname
        target_node   = module.music.target_node
        interface     = module.music.interface
        vm_type       = module.music.vm_type
        public_key    = var.pve_infra_ssh_public_key
        root_password = var.guest_root_password
      }
    ],
    [
      for name, vm in module.talos_cluster.control_plane_vms :
      {
        vmid        = vm.vmid
        hostname    = vm.hostname
        target_node = vm.target_node
        interface   = vm.interface
        ip          = vm.ip
        vm_type     = "talos"
        role        = "control-plane"
      }
    ],
    [
      for name, vm in module.talos_cluster.worker_vms :
      {
        vmid        = vm.vmid
        hostname    = vm.hostname
        target_node = vm.target_node
        interface   = vm.interface
        ip          = vm.ip
        vm_type     = "talos"
        role        = "worker"
      }
    ]
  )
}

output "talosconfig" {
  value     = module.talos_cluster.talosconfig
  sensitive = true
}

output "kubeconfig" {
  value     = module.talos_cluster.kubeconfig
  sensitive = true
}