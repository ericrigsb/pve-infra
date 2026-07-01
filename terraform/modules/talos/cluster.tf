resource "talos_machine_secrets" "machine_secrets" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [for config in var.talos_controlplane_config : config.ip]
}

data "talos_machine_configuration" "machineconfig_cp" {
  for_each         = { for machine in var.talos_controlplane_config : machine.name => machine }
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${each.value.ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  for_each                    = { for machine in var.talos_controlplane_config : machine.name => machine }
  depends_on                  = [
    proxmox_virtual_environment_vm.talos_cp,
    null_resource.wait_for_cp_boot
  ]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp[each.value.name].machine_configuration
  node                        = each.value.ip
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/vda"
        },
        time = {
          servers = ["/dev/ptp0"]
        },
        network = {
          nameservers = var.dns_servers != null ? var.dns_servers : []
        },
        sysctls = {
          "user.max_user_namespaces" = "28633"
        },
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        },
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = {
            "$patch" = "delete"
          }
        }
      },
      cluster = {
        allowSchedulingOnControlPlanes = true,
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
          "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        ]
      }
    })
  ]
}

resource "null_resource" "wait_for_cp_boot" {
  depends_on = [proxmox_virtual_environment_vm.talos_cp]

  provisioner "local-exec" {
    command = "sleep 60"
  }
}

data "talos_machine_configuration" "machineconfig_worker" {
  for_each         = { for machine in var.talos_worker_config : machine.name => machine }
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.talos_controlplane_config[0].ip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker_config_apply" {
  for_each                    = { for machine in var.talos_worker_config : machine.name => machine }
  depends_on                  = [
    proxmox_virtual_environment_vm.talos_worker,
    null_resource.wait_for_worker_boot
  ]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker[each.value.name].machine_configuration
  node                        = each.value.ip
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/vda"
        },
        time = {
          servers = ["/dev/ptp0"]
        },
        network = {
          nameservers = var.dns_servers != null ? var.dns_servers : []
        },
        sysctls = {
          "user.max_user_namespaces" = "28633"
        },
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
      }
    })
  ]
}

resource "null_resource" "wait_for_worker_boot" {
  depends_on = [proxmox_virtual_environment_vm.talos_worker]

  provisioner "local-exec" {
    command = "sleep 60"
  }
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.talos_controlplane_config[0].ip
}

# Only check health after initial bootstrap, not during every plan
resource "null_resource" "cluster_ready" {
  depends_on = [talos_machine_bootstrap.bootstrap]
  
  triggers = {
    cluster_id = talos_machine_secrets.machine_secrets.id
  }
}

data "talos_cluster_health" "health" {
  count                = var.check_cluster_health ? 1 : 0
  depends_on           = [null_resource.cluster_ready]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  control_plane_nodes  = [for config in var.talos_controlplane_config : config.ip]
  worker_nodes         = [for config in var.talos_worker_config : config.ip]
  endpoints            = [for config in var.talos_controlplane_config : config.ip]
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap, data.talos_cluster_health.health]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.talos_controlplane_config[0].ip
}