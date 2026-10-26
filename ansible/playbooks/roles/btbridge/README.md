# btbridge (sendspin-bt-bridge LXC)

Bluetooth bridge that makes the Bose patio speaker a Sendspin player for Music
Assistant. CT **108** on **pve2**, IP **10.0.4.20/24**, hostname `btbridge`.

Music Assistant Sendspin server: `10.0.4.14:8927`.

## Why the container is created out-of-band

The bridge cannot run its own `bluetoothd` — `AF_BLUETOOTH` is unavailable in
LXC network namespaces. Instead the **host** runs `bluetoothd` and the
container reaches it over a bind-mounted host D-Bus socket at `/bt-dbus`.

That requires LXC config lines that `bpg/proxmox` 0.109.0 cannot express. The
provider has no raw-config attribute, and its `mount_point` block maps to
Proxmox `mpN` storage mounts (it requires a `volume`), so it cannot bind-mount
`/run/dbus`. The required lines are:

```
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: c 166:* rwm
lxc.cgroup2.devices.allow: c 13:* rwm
lxc.cgroup2.devices.allow: c 10:232 rwm
lxc.mount.entry: /run/dbus bt-dbus none bind,create=dir 0 0
```

`c 166:*` is the Bluetooth HCI character device and is what actually matters for
an onboard CNVi radio, which surfaces as `/dev/hci0` rather than a USB device.
Only add the following if a **USB** dongle is ever used instead — answering `n`
to the script's USB prompt keeps the container from being granted access to
every USB device on the host:

```
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none rbind,optional,create=dir 0 0
```

So the container is created by the upstream script and then **imported** into
Terraform, matching how `gitea` (103), `streamer` (105) and `dns01`/`dns02`
(106/107) are already managed. `terraform/btbridge.tf` tracks identity, sizing,
network and features; it does not own those `lxc.*` lines.

**Verify after any `terraform apply` that the `lxc.*` lines are still in
`/etc/pve/lxc/108.conf`.** Terraform re-applies container config on each apply.
Check Bluetooth health on the **host** (`bluetoothctl list` on pve2), not in the
container — the role masks `bluetooth.service` there on purpose, so
`systemctl is-active bluetooth` inside CT 108 reports inactive by design. From
the container, verify the bind-mounted host socket instead:
`pct exec 108 -- /usr/local/bin/btctl show`.

## Prerequisites on pve2

Both verified on this host:

- CPU: pve2 was confirmed to have `sse4_2` and `popcnt` in `/proc/cpuinfo`, so it
  meets the `x86-64-v2` baseline. Recorded as a verified property of this host.
  Nothing upstream — neither `install.sh` nor the project README — states a hard
  instruction-set requirement, so treat this as "pve2 is known good", not as a
  documented constraint that needs re-checking elsewhere.
- Bluetooth radio present and healthy. `btusb`/`btintel`/`btmtk` are bound to an
  onboard Intel 8265/8275 CNVi card (`02:00.0`, `8086:24fd`), and BlueZ reports:

  ```
  Controller 34:41:5D:B5:5B:F2 pve2 [default]
  hci0:   Primary controller
          current settings: powered ssp br/edr le secure-conn wide-band-speech
  ```

  Class `0x40010c` (Audio/Video) with BR/EDR and `wide-band-speech` — correct for
  an A2DP sink. pve3 is wired-only (I219-LM, no wireless function at all) and
  has no radio, which is why the container lives on pve2.
- `bluez` must be installed on the host. The kernel drivers were present before
  it, so `lsmod` alone is not proof of a working controller — check
  `bluetoothctl list` for a `Controller` line.
- The radio must not be claimed by another guest. `terraform/docker.tf` sets
  `usb_mapping = "usb-share"` on VM 100, which resolves to the host-level
  `/etc/pve/usb.cfg`. On this cluster that file does not exist, so VM 100's
  `usb0: mapping=usb-share` is a dangling reference and nothing claims the
  radio. Worth cleaning up separately.

## Create

On pve2 as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/trudenboy/sendspin-bt-bridge/main/deployment/lxc/proxmox-create.sh)
```

Answer the prompts with:

| Prompt | Answer |
| --- | --- |
| Container ID | `108` |
| Hostname | `btbridge` |
| RAM (MB) | `768` |
| Disk size (GB) | `8` |
| CPU cores | `2` |
| Storage pool | `local-lvm` |
| Network bridge | `vmbr0` |
| IP address (CIDR) | `10.0.4.20/24` |
| Gateway | `10.0.4.1` |
| GitHub repo | `trudenboy/sendspin-bt-bridge` |
| GitHub branch | `v2.76.4` |
| Pass through USB Bluetooth adapter? | `n` |

Decline the USB passthrough: the radio is onboard CNVi and is reached through
`/dev/hci0` (char `166:*`), so granting `c 189:*` would only hand the container
every USB device on the host for nothing. The script installs bluez on the host
if missing, installs the app, and adds the D-Bus mount.

Pin the branch to `v2.76.4` (as in the table above) — that is what makes the
install reproducible, since the script otherwise tracks `main`.

### Changing the pinned version

Update `btbridge_app_version` in `roles/btbridge/defaults/main.yml` **and** the
two references above it in this file, then re-run the in-container installer. It
preserves `/config/config.json`, so the stored Music Assistant token survives:

```bash
pct exec 108 -- bash -c 'curl -fsSL https://raw.githubusercontent.com/trudenboy/sendspin-bt-bridge/main/deployment/lxc/install.sh | bash -s -- --branch v2.76.4'
```

**The installer does not restart a running bridge.** Its final step only starts
services that are *inactive*, so on an already-running container it prints
`✓ sendspin-client already running` and the old process stays in memory. The new
code is on disk but not loaded until you restart:

```bash
pct exec 108 -- systemctl restart sendspin-client
```

Without that restart the upgrade looks like a no-op in the web UI, because the
running process is still the previous release.

Confirm what is actually installed and running. The app reports its version from
the installed **package metadata**, not from `/opt/sendspin-client/VERSION`:

```bash
pct exec 108 -- cat /opt/sendspin-client/.release-ref          # branch/tag that was installed
pct exec 108 -- python3 -c 'from importlib.metadata import version; print(version("sendspin-bt-bridge"))'
```

Both must match the `--branch` above. If `.release-ref` shows the new version but
`importlib.metadata` shows the old one, the editable reinstall
(`pip3 install -e`) did not refresh the distribution metadata — force it:

```bash
pct exec 108 -- bash -c 'pip3 install --break-system-packages --no-deps --force-reinstall -e /opt/sendspin-client'
```

**Ignore the pip dependency-conflict errors.** `requirements.txt` is exported with
`uv export --no-emit-project`, so it carries dependencies but not the project
itself. The installer's first pip call installs the new dependencies while the
*previous* release is still the installed distribution, so pip compares the new
pins against the old release's recorded pins and reports them as conflicts, e.g.:

```
sendspin-bt-bridge 2.75.0 requires aiosendspin==6.1.1, but you have aiosendspin 9.1.1
sendspin-bt-bridge 2.75.0 requires dbus-fast==5.0.22, but you have dbus-fast 5.2.0
```

The second pip call then reinstalls the project, which resolves them. These
warnings recur on every version change and are harmless. A `sendspin <version>`
line in the same block is a leftover pre-rename distribution in site-packages,
also harmless.

## Import into Terraform

```bash
cd terraform
terraform import module.btbridge.proxmox_virtual_environment_container.lxc pve2/108
```

The import block is already declared in `terraform/imports.tf`, so a plain
`terraform plan` is enough to adopt the container — the explicit
`terraform import` above is only needed if you want to import before pushing.

Expect a small benign diff on the first plan. The create script does not set
everything `terraform/btbridge.tf` declares, so Terraform will want to
reconcile: `memory_swap` (script leaves the PVE default, we pin 768),
`startup_order` 40, `nameservers`, and the `imported;bluetooth;sendspin` tags.
All safe to apply.

**Ordering matters:** create CT 108 *before* pushing. `terraform plan` on a PR
that touches `terraform/**` fails on the import block while the container does
not exist yet.

## Pair the speaker

Bluetooth runs on the host; `btctl` is a wrapper that points `bluetoothctl` at
the bind-mounted host socket.

**Use the absolute path.** `pct exec` does not inherit a login `PATH`, so
`pct exec 108 -- btctl` fails with a misleading
`lxc-attach: ... No such file or directory - Failed to exec "btctl"` even though
the wrapper exists at `/usr/local/bin/btctl`. The unit sets an explicit
`PATH=`, but `pct exec` does not use it.

```bash
pct exec 108 -- /usr/local/bin/btctl
# power on / agent on / default-agent / scan on / pair <MAC> / trust <MAC> / connect <MAC> / quit
```

Non-interactively:

```bash
pct exec 108 -- /usr/local/bin/btctl power on
pct exec 108 -- /usr/local/bin/btctl agent on
pct exec 108 -- /usr/local/bin/btctl default-agent
pct exec 108 -- /usr/local/bin/btctl scan on
sleep 10
pct exec 108 -- /usr/local/bin/btctl devices
pct exec 108 -- /usr/local/bin/btctl pair    <MAC>
pct exec 108 -- /usr/local/bin/btctl trust   <MAC>
pct exec 108 -- /usr/local/bin/btctl connect <MAC>
```

`Unable to open mgmt_socket` on the first line of `btctl show` is expected and
benign. That is the local AF_BLUETOOTH management socket, which is not reachable
across the D-Bus bind-mount; every command above goes through the
`org.bluez.Adapter1` D-Bus API instead, which does work.

Then add the speaker at `http://10.0.4.20:8080` and restart the service:

```bash
pct exec 108 -- systemctl restart sendspin-client
```

In the **Music Assistant** tab, either let the bridge discover MA or set
`SENDSPIN_SERVER=10.0.4.14` with `SENDSPIN_PORT=8927`, then use **Get token** to
store the MA API token.

`SENDSPIN_SERVER=auto` is the default and already works here — mDNS resolved MA
on first boot (`Server: Auto-discovered (mDNS)`), so pinning the IP is optional.

## Port map — do not mix these up

| Port | What it is | Where it is configured |
| --- | --- | --- |
| `8927` | MA **Sendspin audio transport** | `SENDSPIN_PORT` (mDNS auto-discovery) |
| `8095` | MA **REST API** — login, library, groups | `MA_API_URL` |
| `8097` | MA secondary/internal API | not used by the bridge |
| `8928` | Bridge's own base listen port | `BASE_LISTEN_PORT` |
| `8080` | Bridge web UI | `WEB_PORT` |

`MA_API_URL` must be `http://10.0.4.14:8095`. Logging in against `8927` returns
`404: Not Found` — that port is the audio stream, not HTTP.

## Use the IP for MA_API_URL, not the `http://` hostname

Setting `MA_API_URL` to `http://music-assistant.mesh.rigsb.net` fails with:

```
Library login failed (Invalid username or password), trying direct HTTP login
MA direct login failed: Permanent Redirect
```

Traefik answers a plain-HTTP request to the mesh hostname with `308 Permanent
Redirect` to the `https://` URL. The bridge posts the login with
`urllib.request` via `safe_urlopen`, which does **not** follow a redirect for a
POST, so it surfaces as an opaque `Permanent Redirect` rather than a useful
auth error. The misleading part is the first line: the library login attempt
really did return 401 for the format it tried, which has nothing to do with the
redirect that actually broke the fallback.

Two working values:

- `http://10.0.4.14:8095` — **preferred.** Same subnet as the bridge, no TLS
  trust to establish, no redirect.
- `https://music-assistant.mesh.rigsb.net` — works, but adds a Traefik hop and
  depends on the container trusting the certificate.

## MA 2.10.x login format

MA `2.10.4` no longer accepts the flat `{"username", "password"}` body; it
returns `401 {"error": "Username and password required"}`. It wants the nested
provider form:

```
POST /auth/login
{"provider_id": "builtin", "credentials": {"username": "...", "password": "..."}}
```

The bridge already tries this as its fallback, so no action is needed here —
recorded only so the `Username and password required` error is not mistaken for
a credential problem later. A trailing slash (`/auth/login/`) is a `404`.

## What Ansible does and does not manage

`ansible/playbooks/btbridge.yml` runs the `common` role, asserts the app and the
D-Bus socket are present, seeds `/config/config.json` only when missing, pins
`WEB_PORT`/`BASE_LISTEN_PORT` in `/etc/environment`, keeps `bluetooth.service`
masked, and ensures `dbus`, `avahi-daemon`, `pulseaudio-system` and
`sendspin-client` are enabled.

It deliberately does **not** template `config.json`. The bridge writes runtime
state into that file (`SECRET_KEY`, `MA_ACCESS_TOKEN`, `MA_REFRESH_TOKEN`,
`LAST_VOLUMES`, `LAST_SINKS`, `CONFIG_SCHEMA_VERSION`), so a managed copy would
destroy the stored Music Assistant token on every run. The web UI is the
supported surface for it.

`btbridge_app_version` in this role's `defaults/main.yml` is an **annotation, not
a control**: it is interpolated only into the failure message printed when the
app is missing (and the matching install command above). Nothing in the role
installs, upgrades, or restarts the bridge, so bumping it changes nothing on
CT 108 — the assertion only checks that `/opt/sendspin-client/sendspin-client`
exists, not which version it is. Applying a version change means re-running
`install.sh` **and** restarting the service, as in "Changing the pinned
version".

## Verify

```bash
pct exec 108 -- systemctl status sendspin-client pulseaudio-system avahi-daemon --no-pager
pct exec 108 -- /usr/local/bin/btctl show      # adapter visible via host D-Bus
pct exec 108 -- pactl list sinks short          # Bluetooth sink present
pct exec 108 -- ls -la /var/run/pulse/native
pct exec 108 -- journalctl -u sendspin-client -f
```

Confirm the deployed release — this is the check that was missing when the
`v2.75.0` → `v2.76.4` bump appeared not to apply:

```bash
pct exec 108 -- cat /opt/sendspin-client/.release-ref
pct exec 108 -- python3 -c 'from importlib.metadata import version; print(version("sendspin-bt-bridge"))'
```

Verified working after first boot:

```
Loaded: loaded (/etc/systemd/system/sendspin-client.service; enabled)
Active: active (running) since Mon 2026-09-28 19:19:02 UTC
   Main PID: 188 (python3)
      Memory: 58.8M
ExecStartPre=... [ -S /var/run/pulse/native ] && [ -e /bt-dbus/system_bus_socket ] && exit 0
```

`No Bluetooth players` at startup is expected until a speaker is paired. A
Bluetooth sink appears in `pactl list sinks short` only once a device is
connected — before that you will see only `fallback` and `sendspin_fallback`.
