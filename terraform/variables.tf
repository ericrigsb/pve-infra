variable "pm_api_url" {
    type        = string
    description = "Proxmox API URL"
}

variable "pm_api_token_id" {
    type        = string
    sensitive   = true
    description = "Proxmox API Token ID"
}

variable "pm_api_token_secret" {
    type        = string
    sensitive   = true
    description = "Proxmox API Token Secret"
}

variable "guest_root_password" {
    type        = string
    sensitive   = true
    description = "Guest Root Password"
}

variable "pve_infra_ssh_key" {
  type          = string
  sensitive     = true
  description   = "SSH Private Key"
}

variable "pve_infra_ssh_public_key" {
    type        = string
    sensitive   = true
    description = "SSH Public Key"
}