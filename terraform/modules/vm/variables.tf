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

# --- Machine ---

variable "machine" {
  type        = string
  default     = null
  description = "QEMU machine type: `pc` (i440FX, the default) or `q35`. Required by guests that boot UEFI firmware."

  validation {
    condition     = var.machine == null || contains(["pc", "q35"], var.machine)
    error_message = "machine must be one of: pc, q35."
  }
}

variable "bios" {
  type        = string
  default     = null
  description = "BIOS implementation, e.g. `ovmf` for UEFI guests. Set this alongside `machine = \"q35\"` rather than relying on the provider inferring it from `efi_disk` — a wrong guess costs a guest recreate, because these are create-time in practice."

  validation {
    condition     = var.bios == null || can(regex("^[a-zA-Z0-9_-]+$", var.bios))
    error_message = "bios must be a bare implementation name such as ovmf, with no spaces or paths."
  }
}

variable "boot_order" {
  type        = list(string)
  default     = null
  description = "Devices in boot priority order, e.g. [\"scsi0\"]. Worth setting on guests with an EFI disk plus a system disk, where the default order can pick the wrong one and present a black screen."

  validation {
    condition     = var.boot_order == null || length(var.boot_order) > 0
    error_message = "boot_order must contain at least one device, or be null."
  }
}

variable "serial_devices" {
  type        = list(object({ device = optional(string, "socket") }))
  default     = []
  description = "Serial console devices, max 4 upstream. `socket` attaches a Proxmox console. This is the only way to read boot output for a guest with no reachable shell — HAOS qualifies, since `ansible.sh` never gets to it."
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

variable "disks" {
  description = <<-EOT
    Disk devices attached to the VM. A single literal disk block cannot express a
    multi-disk guest, and HAOS requires two: an EFI vars disk and the system
    disk.

    `interface` must be unique across entries and is what PVE records as
    scsi0/scsi1/..., so set it explicitly rather than relying on list position.

    `size` accepts values below 1 GiB. The previous single-disk variable
    required >= 1, which was fine when every guest had one real disk; the HAOS
    EFI vars disk is a few tens of MB, so the floor is now > 0. Do not tighten
    it back without checking that disk.
  EOT
  type = list(object({
    interface    = string
    datastore_id = optional(string, "local-lvm")
    iothread     = optional(bool, true)
    replicate    = optional(bool, false)
    size         = number

    # Mutually exclusive ways to populate the disk at create time. Both are
    # ignored by the provider once the guest exists, so neither will silently
    # re-import a running disk.
    #
    # `file_id` takes a URL, which the provider downloads into `datastore_id`.
    # That is how a published image (e.g. a Home Assistant OS qcow2) gets in.
    #
    # `import_from` takes a volume already present in storage
    # (`datastore_id:volume/volid`), not a URL.
    file_id     = optional(string)
    import_from = optional(string)
  }))

  validation {
    condition     = length(var.disks) > 0
    error_message = "At least one disk must be defined."
  }

  validation {
    condition     = length(distinct([for d in var.disks : d.interface])) == length(var.disks)
    error_message = "Each disk must use a distinct interface (e.g. scsi0, scsi1)."
  }

  validation {
    condition     = alltrue([for d in var.disks : d.size > 0])
    error_message = "Disk size must be greater than 0."
  }

  validation {
    condition = alltrue([
      for d in var.disks : d.file_id == null || d.import_from == null
    ])
    error_message = "A disk accepts either file_id or import_from, not both."
  }
}

variable "efi_disk" {
  description = <<-EOT
    Optional OVMF EFI vars disk. Required by firmware-booting guests such as
    Home Assistant OS, which will not boot from the default SeaBIOS without
    one. There is no `size` here: the provider takes it from `type`, and PVE
    only accepts the small OVMF sizes.

    Leave null (the default) for guests that boot with SeaBIOS. A null emits
    no `efi_disk` block at all, rather than a block with null members.
  EOT
  type = object({
    datastore_id      = optional(string, "local-lvm")
    pre_enrolled_keys = optional(bool, false)
    type              = optional(string, "4m")
  })
  default = null

  validation {
    condition     = var.efi_disk == null || contains(["2m", "4m", "8m"], var.efi_disk.type)
    error_message = "efi_disk type must be one of: 2m, 4m, 8m."
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

# --- Startup ---

variable "startup_order" {
  type        = number
  description = "Proxmox startup order"
  default     = 0
}

variable "startup_up_delay" {
  type        = number
  description = "Delay (seconds) after starting this VM"
  default     = 0
}

variable "startup_down_delay" {
  type        = number
  description = "Delay (seconds) before stopping this VM"
  default     = 0
}