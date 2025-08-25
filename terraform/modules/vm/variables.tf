variable "name" {
  type        = string
  description = "Name of the VM and Proxmox node."
}

variable "node_name" {
  type        = string
  description = "Proxmox node to deploy the VM to."
}

variable "vm_id" {
  type        = number
  description = "Unique ID to assign to the VM."
  validation {
    condition     = var.vm_id > 0
    error_message = "VM ID must be greater than 0."
  }
}

variable "on_boot" {
  type        = bool
  default     = true
  description = "Whether to start the VM automatically on node boot."
}

variable "reboot" {
  type        = bool
  default     = false
  description = "Whether to reboot the VM after changes are applied."
}

variable "reboot_after_update" {
  type        = bool
  default     = false
  description = "Reboot the VM after a guest agent update."
}

variable "stop_on_destroy" {
  type        = bool
  default     = true
  description = "Gracefully stop the VM before destroying it."
}

variable "scsi_hardware" {
  type        = string
  default     = "virtio-scsi-single"
  description = "SCSI controller model."
  validation {
    condition     = contains(["virtio-scsi-single", "virtio-scsi-pci", "lsi", "lsi53c810"], var.scsi_hardware)
    error_message = "Invalid SCSI hardware option."
  }
}

variable "tags" {
  type        = string
  default     = ""
  description = "Semicolon-delimited list of VM tags."
}

# --- Agent ---

variable "agent_enabled" {
  type        = bool
  default     = true
  description = "Enable QEMU guest agent."
}

variable "agent_timeout" {
  type        = string
  default     = "15m"
  description = "Agent operation timeout."
}

variable "agent_trim" {
  type        = bool
  default     = true
  description = "Enable guest TRIM support."
}

# --- CPU ---

variable "cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores."
}

variable "cpu_flags" {
  type        = list(string)
  default     = []
  description = "Optional CPU flags (e.g. ['+aes'])."
}

variable "cpu_hotplugged" {
  type        = number
  default     = 0
  description = "Whether to allow CPU hotplug."
}

variable "cpu_limit" {
  type        = number
  default     = 1.0
  description = "CPU usage limit (0 = no limit)."
}

variable "cpu_numa" {
  type        = bool
  default     = false
  description = "Enable NUMA."
}

variable "cpu_sockets" {
  type        = number
  default     = 1
  description = "Number of CPU sockets."
}

variable "cpu_type" {
  type        = string
  default     = "x86-64-v2-AES"
  description = "Type of CPU to emulate."
}

variable "cpu_units" {
  type        = number
  default     = 1024
  description = "Relative CPU weight."
}

# --- Disk ---

variable "disk_datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Datastore where the disk will be stored."
}

variable "disk_interface" {
  type        = string
  default     = "scsi0"
  description = "Disk interface identifier (e.g. scsi0, sata0)."
}

variable "disk_iothread" {
  type        = bool
  default     = true
  description = "Enable IO thread for disk."
}

variable "disk_replicate" {
  type        = bool
  default     = false
  description = "Enable replication for disk (if HA is used)."
}

variable "disk_size" {
  type        = number
  default     = 8
  description = "Disk size in GiB."
  validation {
    condition     = var.disk_size >= 1
    error_message = "Disk size must be at least 1 GiB."
  }
}

# --- Memory ---

variable "memory_dedicated" {
  type        = number
  default     = 2048
  description = "Dedicated RAM in MB."
}

variable "memory_floating" {
  type        = number
  default     = 0
  description = "Additional memory that can be ballooned (MB)."
}

variable "memory_keep_hugepages" {
  type        = bool
  default     = false
  description = "Keep hugepages enabled."
}

variable "memory_shared" {
  type        = number
  default     = 0
  description = "Memory shares."
}

# --- Network (multi-interface support) ---

variable "network_devices" {
  description = "List of network device configurations. Each object can have bridge, firewall, and model."
  type = list(object({
    bridge   = string
    firewall = optional(bool, false)
    model    = optional(string, "virtio")
  }))
  default = [
    {
      bridge   = "vmbr0"
      firewall = false
      model    = "virtio"
    }
  ]
  validation {
    condition = alltrue([
      for d in var.network_devices :
      contains(["virtio", "e1000", "rtl8139", "vmxnet3"], lookup(d, "model", "virtio"))
    ])
    error_message = "Each network device model must be one of: virtio, e1000, rtl8139, vmxnet3."
  }
}

# --- OS ---

variable "os_type" {
  type        = string
  default     = "l26"
  description = "Guest operating system type."
  validation {
    condition     = contains(["l26", "w10", "w2k19", "other"], var.os_type)
    error_message = "Unsupported OS type."
  }
}

# --- USB ---

variable "usb_mapping" {
  type        = string
  default     = ""
  description = "USB mapping ID (optional)."
}

variable "usb_usb3" {
  type        = bool
  default     = false
  description = "Set to true if USB 3.0 is required."
}

# --- Network Name Output ---

variable "network_name" {
  type = string
  default = "ens18"
  description = "Nic name for further external scripting."
}