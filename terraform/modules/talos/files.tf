resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  for_each      = toset(var.proxmox_nodes)
  content_type  = "iso"
  datastore_id  = "local"
  node_name     = each.value
  file_name     = "talos-v${var.talos_version}-nocloud-amd64.iso"
  url           = "https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v${var.talos_version}/nocloud-amd64.iso"
  overwrite     = false
}