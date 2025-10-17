variable "proxmox_nodes" {
  description = "Names of the Proxmox nodes, used to download and reference node images"
  type        = list(string)
  default     = ["pve0", "pve1"]
}

variable "talos_version" {
  type    = string
  default = "1.10.4"
}

variable "cluster_name" {
  type    = string
  default = "homelab"
}

variable "default_gateway" {
  type    = string
  default = "10.0.4.1"
}

variable "dns_servers" {
  type = list(string)
  default = [ "10.0.4.1" ]
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_device_vlan_id" {
  type    = number
  default = null
}

variable "tags" {
  type        = string
  default     = ""
  description = "Semicolon-delimited list of tags."
}

variable "talos_controlplane_config" {
  description = "Machine configuration of control-plane nodes"
  type = list(object({
    id              = number
    ip              = string
    name            = string
    node            = string
    cpu_cores       = number
    cpu_type        = string
    memory          = number
    disk_size       = number
  }))
  default = [{
    id        = 201
    name      = "talos-cp-01"
    ip        = "10.0.4.2"
    node      = "pve1"
    cpu_cores = 2
    cpu_type = "host"
    memory    = 2048
    disk_size = 10
    }]
}

variable "talos_worker_config" {
  description = "Machine configuration of worker nodes"
  type = list(object({
    id        = number
    ip        = string
    name      = string
    node      = string
    cpu_cores = number
    cpu_type  = string
    memory    = number
    disk_size = number
  }))
  default = [{
    id        = 211
    name      = "talos-worker-01"
    ip        = "10.0.4.11"
    node      = "pve1"
    cpu_cores = 1
    cpu_type = "host"
    memory    = 1024
    disk_size = 32
    }, {
    id        = 212
    name      = "talos-worker-02"
    ip        = "10.0.4.12"
    node      = "pve1"
    cpu_cores = 1
    cpu_type = "host"
    memory    = 1024
    disk_size = 32
    }]
}