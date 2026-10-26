resource "proxmox_download_file" "talos_nocloud_image" {
  for_each      = toset(var.proxmox_nodes)
  content_type  = "iso"
  datastore_id  = "local"
  node_name     = each.value
  file_name     = "talos-v${var.talos_version}-nocloud-amd64.iso"
  url           = "https://factory.talos.dev/image/${var.talos_image_schematic_id}/v${var.talos_version}/nocloud-amd64.iso"
  overwrite     = false
}

moved {
  from = proxmox_virtual_environment_download_file.talos_nocloud_image
  to   = proxmox_download_file.talos_nocloud_image
}