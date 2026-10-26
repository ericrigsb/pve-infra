module "music" {
  source = "./modules/lxc"

  providers = {
    proxmox = proxmox.music
  }

  node_name         = "pve3"
  lxc_id            = 105
  start_on_boot     = true
  init_hostname     = "streamer"
  os_template       = ""
  tags              = "imported"
  disk_datastore_id = "local-lvm"
  disk_size         = 8
  memory_dedicated  = 512
  memory_swap       = 512
  unprivileged      = true

  # Analog line-in capture comes from a Cubilux HLMS-C4 USB sound card
  # (USB 0bda:4dc7), which replaced the onboard CX20632 front-panel input.
  # That codec only exposes a mono "Headset Mic" pin - it has no line-in pin -
  # which is why the previous capture was mono.
  #
  # The adapter is pinned to card 1 on pve3 and exposes two capture PCMs:
  #   /dev/snd/pcmC1D0c = Microphone (USB interface 1, 44.1/48 kHz)
  #   /dev/snd/pcmC1D1c = Line In    (USB interface 2, 48 kHz, 16/24-bit) <- used
  # The client refers to the card by its stable name (CARD=HLMSC4), but these
  # paths are index-based and the index is NOT stable on its own: probe order
  # between snd_usb_audio and snd_hda_intel can put the adapter on card 0 and
  # the onboard PCH on card 1 (which has no pcmC1D1c). pve3 pins it with
  # `options snd_hda_intel index=0` / `options snd_usb_audio index=1` in
  # /etc/modprobe.d/99-sound-order.conf - host config, not managed here.
  #
  # device_passthrough is deliberately NOT set here. Proxmox allows only root@pam
  # to change LXC device passthrough (PVE::LXC::check_ct_modify_config_perm:
  # "configuring device passthrough is only allowed for root@pam"), and CI runs
  # as an API token whose identity can never equal root@pam - so any apply that
  # touched devN failed with HTTP 403. The module freezes the attribute with
  # `ignore_changes` and the real keys are set by hand on pve3; see
  # ansible/playbooks/roles/streamer/README.md.
  #
  # Intended passthrough (dev0-dev3; the old card-0 keys dev4-dev9 must be gone):
  #   /dev/snd/controlC1  /dev/snd/pcmC1D1c  /dev/snd/seq  /dev/snd/timer
  #
  # NOTE: Proxmox refuses to start the container when a passthrough path is
  # missing (PVE::LXC::Tools::get_device_mode_and_rdev: "Device ... does not
  # exist"), so CT 105 requires this USB adapter to be both plugged in and at
  # card 1 to boot. The index pin above is what keeps the second half true.

  network_interfaces = [
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

  ip_configs = [
    {
      ipv4_address = "10.0.4.19/24"
      ipv4_gateway = "10.0.4.1"
    }
  ]

  nameservers   = ["10.0.4.5","10.0.4.3","10.0.4.1"]
  startup_order = 40

  features = {
    nesting = true
  }
}