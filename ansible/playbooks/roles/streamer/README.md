# streamer (analog line-in capture LXC)

Captures an analog line-level source with ALSA and feeds it to Music Assistant's
Sendspin server at `10.0.4.14:8927`. CT **105** on **pve3**, IP
**10.0.4.19/24**, hostname `streamer`.

## The capture device

Input is a **Cubilux HLMS-C4** USB sound card. It replaced the onboard CX20632
front-panel jack, which is a *headset* codec: its only capture pin is a mono
"Headset Mic", so the old capture was mono and had no line level.

The adapter is ALSA **card 1**, device **1**:

| Node                 | Role                          | Rates              |
| -------------------- | ----------------------------- | ------------------ |
| `/dev/snd/pcmC1D0c`  | Microphone (USB interface 1)  | 44.1 / 48 kHz      |
| `/dev/snd/pcmC1D1c`  | **Line In** (USB interface 2) | 48 kHz, 16/24-bit  |

The card **id** (`HLMSC4`) is stable; the card **index** is not, so it is pinned
on pve3 — see [the ALSA card index](#the-alsa-card-index) below. The client
names the card by its id and uses `plughw:` because it hard-codes
`48000/S16_LE/2ch`:

```yaml
# ansible/playbooks/roles/streamer/defaults/main.yml
streamer_soundcard: "plughw:CARD=HLMSC4,DEV=1"
```

## The ALSA card index

`plughw:CARD=HLMSC4,DEV=1` is resolved by *name*, so the client itself does not
care which index the adapter lands on. The LXC `devN` keys do: they are paths,
and `pcmC1D1c` means "card 1".

The index is assigned by the kernel in **probe order**, which is not
deterministic between boots — `snd_usb_audio` and `snd_hda_intel` race, and
either can claim card 0. On 2026-10-19 a pve3 reboot put the adapter on card 0
and the onboard PCH on card 1. The PCH exposes no `pcmC1D1c` — only `pcmC1D0c`,
`pcmC1D0p` and the HDMI playback nodes — so starting the container failed with:

```
TASK ERROR: Device /dev/snd/pcmC1D1c does not exist
```

CT 105 stayed down. The adapter was fine (`lsusb` showed `0bda:4dc7`); only the
index had moved, so every index-based `devN` path pointed at the wrong card.

pve3 therefore pins the order in `/etc/modprobe.d/99-sound-order.conf`:

```
# Keep the onboard HDA codec at card 0 and the Cubilux HLMS-C4 USB sound card
# at card 1. CT 105's devN keys are index-based (controlC1, pcmC1D1c); without
# this, probe order can flip and the container will not start.
options snd_hda_intel index=0
options snd_usb_audio index=1
```

applied with `update-initramfs -u` and a reboot. The modules are already loaded,
so only a reboot — or an unload/reload with nothing holding the devices —
re-applies the option. This is pve3 host config and is **not** in this repo, for
the same reason `devN` is not: see `AGENTS.md` §11.

Verify after a pve3 reboot:

```bash
for c in /sys/class/sound/card*; do echo "${c##*/} -> $(cat "$c/id")"; done
# expect: card0 -> PCH   card1 -> HLMSC4
ls -l /dev/snd/pcmC1D1c
pct status 105
```

If `pct start` fails again, check the adapter is enumerated at all
(`lsusb | grep 0bda:4dc7`) and what index it actually got before re-pointing
`devN` — do not assume the pin is in force. If it recurs on host reboots even
with the pin, the container is racing USB enumeration and wants a start guard
(a `systemd` `.path` unit on `/dev/snd/pcmC1D1c` with `start_on_boot = false`).

## Why the passthrough is applied out-of-band

Proxmox allows only `root@pam` to change LXC device passthrough — from
`PVE::LXC::check_ct_modify_config_perm`:

```perl
} elsif ($opt =~ m/^dev\d+$/) {
    raise_perm_exc("configuring device passthrough is only allowed for root\@pam");
}
```

A request authenticated with an API token has the identity
`user@realm!tokenid`, which never equals the literal `root@pam`, so **no
Terraform apply can set `devN`** — the `bpg/proxmox` provider sends the field
whenever it changes (`if d.HasChange(mkDevicePassthrough)`) and Proxmox answers
HTTP 403. `terraform/streamer.tf` therefore no longer declares
`device_passthrough`, and `modules/lxc` freezes the attribute with
`ignore_changes` so an apply does not try to reconcile (or remove) the live
keys.

This mirrors how `btbridge` (CT 108) is handled: Terraform owns identity,
sizing, network and features; the passthrough itself is not its to own.

## Applying it (on pve3, as root)

Replace the old card-0 set (`dev0`–`dev9`: `controlC0`, the `pcmC0D*`/`hwC0D*`
nodes, `seq`, `timer`) with the four Line-In keys:

```bash
pct set 105 \
  --dev0 /dev/snd/controlC1 \
  --dev1 /dev/snd/pcmC1D1c \
  --dev2 /dev/snd/seq \
  --dev3 /dev/snd/timer \
  --delete dev4,dev5,dev6,dev7,dev8,dev9
pct reboot 105
```

The Proxmox UI does the same thing: **pve3 → 105 (streamer) → Resources →
Device Passthrough** — remove the ten `controlC0`/`pcmC0*`/`hwC0*`/`seq`/`timer`
entries and add the four above.

`devN` paths are resolved at container start, so **CT 105 will not boot while
the adapter is unplugged — or while it sits at a different card index** (Proxmox
dies on a missing path; see [the ALSA card index](#the-alsa-card-index)). That
is the accepted cost of replacing the onboard input.

## Verify

The device nodes are `root:root`, so `arecord`/`amixer` as the unprivileged
`eric` user fail — run these with `sudo` inside CT 105:

```bash
# Close to the product spec: 48000 Hz, S16_LE + S24_3LE, 2 channels
sudo arecord -D plughw:CARD=HLMSC4,DEV=1 --dump-hw-params /dev/null
sudo arecord -D plughw:CARD=HLMSC4,DEV=1 -f S16_LE -r 48000 -c 2 -d 5 /tmp/line.wav
```

`streamer-sendspin-source.service` should be `active`, and Music Assistant
should see audio arriving. If capture is silent, check the Line capture mixer
state (`amixer -c HLMSC4 scontrols` / `sget`) before assuming a wiring fault.

## If the client starts minutes after boot

The unit is ordered `After=network-online.target`, so anything that delays that
target delays the player in Music Assistant. Symptom: the source only appears
several minutes after CT 105 boots and `systemctl is-system-running` says
`degraded`.

```bash
systemctl --failed            # networking.service + ifupdown-wait-online.service
cat /etc/network/interfaces   # an `auto ethN` block for a NIC that isn't there
ls /sys/class/net             # eth0, lo
```

A leftover stanza for an interface the container does not have makes `ifup -a`
fail, so the wait-online unit never succeeds and the client waits out the
ifupdown timeout first. Measured 2026-10-19: boot 18:33:18 -> client 18:38:20
(**~5 min**); after deleting the block, boot 18:47:12 -> client 18:47:14
(**2 s**), with `networking.service` and `ifupdown-wait-online.service` both
`active (exited)`.

Fix it **inside the guest** (delete the `auto ethN` line and its block, then
`pct reboot 105`). Do not go looking for a `net1` in the container config:
`pct config 105 | grep '^net'` shows `net0` only and Terraform declares a single
NIC. Proxmox rewrites `/etc/network/interfaces` on every container start, but
only regenerates the blocks whose interface is named in the config's `netN`
keys; every other stanza is preserved verbatim, so a stale one survives reboots
and only an in-guest edit removes it. `backup` (CT 101) still carries the same
leftover. See AGENTS.md #17.

## Naming in Music Assistant

The client announces a single name (`streamer_sendspin_client_name`), and MA
shows it in two places while keeping its own label in a third:

| where | shown as | owned by |
|---|---|---|
| Browse -> the audio source | `info.name` from the client hello | this role |
| now-playing title while it plays | same hello name | this role |
| Settings -> Players row | MA's configured player name | Music Assistant |

So renaming the player in MA does not rename the Browse entry, and changing
`streamer_sendspin_client_name` does not rename an already-renamed player. The
stable key across all three is the **client id** (derived from the Noise identity
in `/var/lib/streamer/sendspin/identity.json`), which is what MA logs as
`Player (type source) registered: <client id>/<name>`. Match on that, not on a
name, when following the source through MA's log. The Browse entry disappears
while the client is disconnected; the player row stays as unavailable.
