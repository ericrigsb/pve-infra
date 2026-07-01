module "talos_cluster" {
  source                   = "./modules/talos"
  cluster_name             = "redcloud"
  talos_image_schematic_id = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
  talos_version            = "1.13.4"
  network_bridge           = "vmbr0"
  network_device_vlan_id   = null
  default_gateway          = "10.0.4.1"
  dns_servers              = [ "10.0.4.1" ]
  proxmox_nodes            = [ "pve1", "pve2", "pve3" ]
  talos_controlplane_config = [{
    id              = 201
    name            = "talos-cp-01"
    ip              = "10.0.4.2"
    node            = "pve1"
    cpu_cores       = 4
    cpu_type        = "host"
    memory          = 3072
    disk_size       = 10
    startup_order   = 50
  },{
    id              = 202
    name            = "talos-cp-02"
    ip              = "10.0.4.6"
    node            = "pve3"
    cpu_cores       = 4
    cpu_type        = "host"
    memory          = 3072
    disk_size       = 32
    startup_order   = 50
  }]
  talos_worker_config = [{
    id        = 211
    name      = "talos-worker-01"
    ip        = "10.0.4.11"
    node      = "pve1"
    cpu_cores = 4
    cpu_type  = "host"
    memory    = 6144
    disk_size = 32
    startup_order = 60
  },{
    id        = 213
    name      = "talos-worker-03"
    ip        = "10.0.4.12"
    node      = "pve1"
    cpu_cores = 4
    cpu_type  = "host"
    memory    = 6144
    disk_size = 32
    startup_order = 60
  },{
    id        = 212
    name      = "talos-worker-02"
    ip        = "10.0.4.13"
    node      = "pve3"
    cpu_cores = 4
    cpu_type  = "host"
    memory    = 5120
    disk_size = 32
    startup_order = 60
  },{
    id        = 214
    name      = "talos-worker-04"
    ip        = "10.0.4.14"
    node      = "pve3"
    cpu_cores = 4
    cpu_type  = "host"
    memory    = 5120
    disk_size = 32
    startup_order = 60
  }]
}