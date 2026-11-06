# docker workload

Files here are the source of truth for the compose stack on the `docker` VM
(Proxmox VM 100, `10.0.4.10`). They are deployed by the Ansible role at
`ansible/playbooks/roles/docker/` to `/mnt/share/projects/redcloud/` on that
host. Editing a file here and merging to `main` is what changes the running
stack — there is no git checkout on the host, and nothing to pull.

## Provenance

Vendored byte-for-byte from the `redcloud` repository at commit `81b8fcb`, which
was the checkout on the host. Content is intentionally unmodified; the role
deploys it as-is. If you change the stack, change it here.

| File | Deploys to | Notes |
|---|---|---|
| `docker-compose.yml` | `/mnt/share/projects/redcloud/docker-compose.yml` | Full stack declaration. Binding: `--remove-orphans` is safe only because this file declares everything. |
| `garage/config.toml` | `/mnt/share/projects/redcloud/garage/config.toml` | Secret-free. Container restart required on change. |
| `restic/backup.sh` | `/etc/backup/backup.sh` | mode 0700. Sources `/etc/backup/restic_env`. |
| `restic/backup.service` | `/etc/systemd/system/backup.service` | No trailing newline; matches the host. |
| `restic/backup.timer` | `/etc/systemd/system/backup.timer` | `OnCalendar=03:00`, `Persistent=true`. No trailing newline; matches the host. |

## Not managed here

- **`.env`** is rendered from `roles/docker/defaults/main.yml` plus three
  secrets injected by CI (`DOCKER_GITEA_RUNNER_REGISTRATION_TOKEN`,
  `DOCKER_GARAGE_RPC_SECRET`, `DOCKER_SLSKD_SLSK_PASSWORD`). It is never
  committed. Set all three in Gitea under Settings → Actions → Secrets. If any
  is unset the role leaves the live `.env` untouched and says so, rather than
  writing a blank value.
- **`/etc/backup/restic_env`, `paths`, `pw`** are root-only and hand-managed.
  The role asserts they exist so the timer is never enabled without its inputs,
  but does not template them.
- **State directories** (`garage/{meta,data}`, `lidarr/config`,
  `uptime-kuma/data`, `gitea-runner/data`, `shared-downloads`) hold the only
  copy of that data. The role creates them if absent and never writes to or
  deletes their contents. `slskd/config` and `soularr/data` are listed too, even
  though their services are disabled, so re-enabling either needs no extra
  setup.
- **`navidrome/data`** exists on the host with no declared service. Stale, left
  alone.

## Before changing an image tag

## Services

Four run: `garage`, `gitea-runner`, `lidarr`, `uptime-kuma`.

`slskd` and `soularr` are **disabled in place** — commented out in
`docker-compose.yml` with a note, not deleted. Soulseek was not wanted, and
`soularr` exists only to bridge lidarr's wanted list into slskd, so it is inert
while slskd is off. To re-enable, uncomment both blocks and restore the six
`SLSKD_*`/`SOULARR` bits listed in the re-enable note in
`roles/docker/defaults/main.yml`.

Their state directories (`slskd/config`, `soularr/data`) still exist on the
host and are left untouched. `--remove-orphans` **will** delete the containers
and their data if you remove a service from the compose file instead of
commenting it out — comment, don't delete.

## Before changing an image tag

Three of the four running services track a floating tag (`gitea/act_runner:latest`,
`lidarr:latest`, `uptime-kuma:2`; only Garage is pinned, at `v2.2.0`). Compose
is reconciled with `--pull missing`, so existing images are *not* re-pulled —
but a new host, a removed image, or a manual `docker compose pull` will pick up
whatever upstream last published. Pin the tags before relying on this directory
as a rollback mechanism.