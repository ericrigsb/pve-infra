module "talos_cluster" {
  source                   = "./modules/talos"
  cluster_name             = "redcloud"
  talos_image_schematic_id = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
  talos_version            = "1.13.4"
  network_bridge           = "vmbr0"
  network_device_vlan_id   = null
  default_gateway          = "10.0.4.1"
  dns_servers              = [ "10.0.4.5","10.0.4.3","10.0.4.1" ]
  # Must be identical for every node. It becomes the service account issuer
  # and audience, so a per-node value would make the control planes reject
  # each other's tokens and cause intermittent 401s from in-cluster clients.
  cluster_endpoint         = "https://10.0.4.2:6443"
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
    # Trimmed 6144 -> 4096 to free RAM on pve1 for the homeassistant guest.
    # pve1 is the only node with any room (pve3 has both DIMM slots full, pve2
    # runs the docker VM). memory_dedicated means there is no balloon, so this
    # only takes effect on a node reboot -- cordon + drain, one node at a time.
    # Measured worker-01 pod use is ~1.4 GiB against 4096 (allocatable ~3.6 GiB),
    # and its requests are ~1.6 GiB, so the margin stays comfortable.
    memory    = 4096
    disk_size = 32
    startup_order = 60
  },{
    id        = 213
    name      = "talos-worker-03"
    ip        = "10.0.4.12"
    node      = "pve1"
    cpu_cores = 4
    cpu_type  = "host"
    # Trimmed 6144 -> 4096 alongside worker-01 to free RAM on pve1 for the
    # homeassistant guest. This is the busiest of the two: mongodb (1152Mi
    # request) plus, once the resource-limit fix lands, immich-server (768Mi)
    # and immich-machine-learning (512Mi). Measured use is ~2.1 GiB and the
    # resulting requests land at ~2.8 GiB of ~3.6 GiB allocatable, so it still
    # schedules with room to spare -- but do not trim this one further without
    # re-checking immich.
    memory    = 4096
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