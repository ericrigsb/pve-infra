terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0-alpha.0"
    }
  }
  backend "s3" {}
}

provider "proxmox" {
  endpoint  = "${var.pm_api_url}"
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"

  ssh {
    agent       = false
    private_key = "${var.pve_infra_ssh_key}"
    username    = "root"
  }
}

provider "talos" {}