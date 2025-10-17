variable "node_name" {
  type        = string
  description = "Proxmox node to deploy the container to."
}

variable "lxc_id" {
  type        = number
  description = "Unique ID to assign to the LXC container."
  validation {
    condition     = var.lxc_id > 0
    error_message = "LXC ID must be greater than 0."
  }
}

variable "start_on_boot" {
  type        = bool
  default     = true
  description = "Start container on Proxmox node boot."
}

variable "unprivileged" {
  type        = bool
  default     = true
  description = "Use unprivileged container."
}

variable "tags" {
  type        = string
  default     = ""
  description = "Semicolon-delimited list of LXC tags."
}

# --- Console ---

variable "console_enabled" {
  type        = bool
  default     = true
  description = "Enable console access."
}

variable "console_tty_count" {
  type        = number
  default     = 2
  description = "Number of TTYs to allocate."
  validation {
    condition     = var.console_tty_count >= 1
    error_message = "TTY count must be at least 1."
  }
}

variable "console_type" {
  type        = string
  default     = "tty"
  description = "Console type (tty or shell)."
  validation {
    condition     = contains(["tty", "shell"], var.console_type)
    error_message = "Console type must be 'tty' or 'shell'."
  }
}

# --- CPU ---

variable "cpu_arch" {
  type        = string
  default     = "amd64"
  description = "CPU architecture to use. Restricted to x86 architectures."

  validation {
    condition     = contains(["amd64", "i386"], var.cpu_arch)
    error_message = "Invalid CPU architecture. Allowed values: amd64, i386 (x86 only)."
  }
}

variable "cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores assigned to the container or VM."

  validation {
    condition     = var.cpu_cores >= 1 && var.cpu_cores <= 64
    error_message = "CPU cores must be between 1 and 64."
  }
}

variable "cpu_units" {
  type        = number
  default     = 1024
  description = "CPU weight for scheduling (relative priority)."

  validation {
    condition     = var.cpu_units >= 2 && var.cpu_units <= 262144
    error_message = "CPU units must be between 2 and 262144."
  }
}

# --- Disk ---

variable "disk_datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Datastore to use for container storage."
}

variable "disk_size" {
  type        = number
  default     = 8
  description = "Size of the root disk in GiB."
  validation {
    condition     = var.disk_size >= 1
    error_message = "Disk size must be at least 1 GiB."
  }
}

# --- Initialization ---

variable "init_hostname" {
  type        = string
  description = "Hostname of the container."
}

variable "nameservers" {
  description = "List of DNS servers to configure in the container."
  type        = list(string)
  default     = []
}

variable "ip_configs" {
  description = "List of IP configs for each network interface. Order must match network_interfaces."
  type = list(object({
    ipv4_address = string
    ipv4_gateway = string
  }))
  default = []
}

# --- Memory ---

variable "memory_dedicated" {
  type        = number
  default     = 512
  description = "Dedicated memory in MB."
}

variable "memory_swap" {
  type        = number
  default     = 512
  description = "Swap memory in MB."
}

# --- Mount Point ---

variable "mountpoint" {
  type = list(object({
    mount_point_acl       = optional(bool,false)
    mount_point_backup    = optional(bool,false)
    mount_point_options   = optional(list(string),[])
    mount_point_path      = optional(string,null)
    mount_point_quota     = optional(bool,false)
    mount_point_read_only = optional(bool, false)
    mount_point_replicate = optional(bool,false)
    mount_point_shared    = optional(bool, false)
    mount_point_volume    = optional(string,null)
  }
  ))
  default = null
}

# --- Device Passthrough ---

variable "device_passthrough" {
  description = "List of device passthrough configurations for the LXC container."
  type = list(object({
    deny_write = optional(bool, false)
    gid        = optional(number, 0)
    mode       = optional(string, "0660")
    path       = optional(string, null)
    uid        = optional(number, 0)
  }))
  default = []
}

# --- Network (multi-interface support) ---

variable "network_interfaces" {
  description = "List of network interface configurations for the LXC container."
  type = list(object({
    bridge      = string
    enabled     = optional(bool, true)
    firewall    = optional(bool, false)
    mac_address = optional(string, "")
    mtu         = optional(number, 0)
    name        = optional(string, "")
    rate_limit  = optional(number, 0)
    vlan_id     = optional(number, 0)
  }))
  default = [
    {
      bridge      = "vmbr0"
      enabled     = true
      firewall    = false
      mac_address = ""
      mtu         = 0
      name        = "eth0"
      rate_limit  = 0
      vlan_id     = 0
    }
  ]
}

# --- Operating System ---

variable "os_template" {
  type        = string
  description = "Storage/template file ID to use for container OS (e.g. 'local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst')."
}

variable "os_type" {
  type        = string
  default     = "debian"
  description = "OS type (e.g. 'debian', 'alpine', 'centos')."
}