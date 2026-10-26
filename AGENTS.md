# AGENTS.md – PVE Infrastructure Guide

This file helps future OpenCode sessions work efficiently in this GitOps-managed infrastructure repository. Every section answers "Would an agent miss this?"

## Quick Start

**Deploy a new app:**
1. Create manifest in `cluster/redcloud/apps/{app-name}/`
2. Push to main → CI/CD workflow triggers → FluxCD auto-reconciles

**Modify infrastructure (VMs/LXCs):**
1. Edit `.tf` file in `terraform/`
2. Push to main → Terraform plan/apply → Ansible runs if VM config changed

**Configure a VM or LXC:**
1. Create playbook at `ansible/playbooks/{hostname}.yml` (name MUST match the VM hostname exactly)
2. Push to main → Terraform provisions → Ansible runs playbook automatically

---

## System Architecture

### Three Execution Layers

1. **Proxmox Infrastructure** (`terraform/`)
   - Provisions VMs and LXC containers on Proxmox cluster
   - Manages Talos Kubernetes cluster (control plane + workers)
   - Modules: `vm/`, `lxc/`, `talos/`

2. **Host Configuration** (`ansible/`)
   - Configures non-Kubernetes VMs/LXCs: Docker, Gitea, DNS, backup, streamer, BT bridge
   - Does NOT touch Talos nodes (those are immutable, managed by Terraform)
   - Playbooks auto-discovered by hostname

3. **Kubernetes Applications** (`cluster/redcloud/`)
   - Apps, databases, infrastructure (Traefik, MetalLB, cert-manager)
   - Managed by FluxCD (GitOps reconciliation)
   - Kustomize-based, with per-namespace secrets

### Directory Structure

```
.
├── terraform/              # Proxmox VM/LXC provisioning & Talos cluster
│   ├── modules/
│   │   ├── vm/            # QEMU VM module
│   │   ├── lxc/           # LXC container module
│   │   └── talos/         # Talos Kubernetes cluster
│   ├── docker.tf          # Docker host (legacy apps + NFS exports)
│   ├── talos.tf           # Kubernetes cluster definition
│   ├── dns01.tf           # Primary DNS/adblock LXC (replaced pihole.tf, #457)
│   ├── dns02.tf           # Secondary DNS LXC
│   ├── gitea.tf, backup.tf, streamer.tf
│   ├── btbridge.tf        # Sendspin BT bridge LXC (privileged, USB passthrough)
│   ├── imports.tf         # Adopts pre-existing PVE guests into state
│   └── providers.tf       # Proxmox + Talos providers
├── ansible/
│   ├── playbooks/
│   │   ├── docker.yml     # Docker host config
│   │   ├── dns01.yml, dns02.yml   # DNS LXCs (replaced pihole.yaml, #457)
│   │   ├── gitea.yaml, backup.yml, streamer.yml, btbridge.yml
│   │   └── roles/         # Reusable roles
│   └── ansible.sh         # Entry point for CI/CD
├── cluster/redcloud/
│   ├── apps/              # App manifests: backrest, docker-shared, immich,
│   │                      #   mailrise, music-assistant, nextcloud, nutweb,
│   │                      #   openspeedtest, unifi-network-application
│   ├── db/                # Database deployments (MongoDB, PostgreSQL, Redis)
│   ├── infra/             # traefik, metallb, cert-manager, external-dns, backups
│   └── flux/              # Flux bootstrap & Kustomizations
└── .gitea/workflows/      # CI/CD automation (Gitea Actions, not GitHub)
    ├── provision.yml      # Terraform + Ansible on main merge
    ├── flux-bootstrap.yaml
    ├── flux-generate-secrets-and-reconcile.yaml
    ├── import.yml
    └── destroy-talos-cluster.yaml
```

> **Read `ls terraform/*.tf` and `ls ansible/playbooks/` before trusting the lists above.** LXCs get renamed over time (`pihole` → `dns01`/`dns02`, `proxy` deleted in #458, Uptime Kuma removed in `44c9e46`), and the prose drifts faster than the file tree.

---

## CI/CD & GitOps Flow

### On Pull Request (before merge)
- **provision.yml**: Terraform validate + plan (`check-terraform`), Ansible lint (`check-ansible`), and a full `--check --diff` dry run of every guest playbook (`check-playbooks`)
- Runs on `terraform/**` or `ansible/**` changes. `check-playbooks` also fires on `workloads/**`
- `check-playbooks` reuses `ansible.sh validate`, so it covers all non-Talos guests with the same playbooks `provision-ansible` will apply after merge
- The dry run is **not a sandbox**: it runs as root against the live guests and handlers fire under `--check`. Every module in use is check-mode aware so nothing mutates, but adding a writing handler or a `check_mode: false` task breaks that — see the note in `provision.yml` before adding either

### On Merge to `main`
- **provision.yml** (terraform apply + ansible):
  1. Terraform init (uses Garage S3 backend)
  2. Terraform apply (creates/updates VMs, LXCs, Talos cluster)
  3. Ansible runs for non-Talos VMs (discovers playbooks by hostname)
- **flux-generate-secrets-and-reconcile.yaml** (on `cluster/redcloud/**` changes):
  1. Creates Kubernetes secrets in app namespaces (Cloudflare, MongoDB, PostgreSQL, Redis, etc.)
  2. Reconciles all Flux Kustomizations
  3. Copies backup scripts ConfigMap to app namespaces

### Backend Configuration
⚠️ **NOTE: Terraform uses Garage S3 for state storage.**

Terraform backend is configured in CI/CD workflows via:
- `GARAGE_ENDPOINT_URL` (S3 endpoint)
- `GARAGE_ACCESS_KEY`, `GARAGE_ACCESS_KEY_SECRET`
- Backend state bucket: `tfstate-pve`, key: `tf-state-pve.tfstate`

Local development requires `backend-config.hcl` (in `.gitignore`; not committed).

⚠️ **The state file is the most sensitive artifact in this estate.** Everything Terraform is handed ends up in it: `talos_machine_secrets` (the Talos CA, etcd/kubelet/bootstrap material — see `terraform/modules/talos/cluster.tf`), plus `guest_root_password`, the Proxmox API tokens and the SSH private key that arrive as variables. Read access to the `tfstate-pve` bucket therefore means read access to the cluster CA and the guest passwords, so treat `GARAGE_ACCESS_KEY`/`GARAGE_ACCESS_KEY_SECRET` as crown-jewel credentials. Never echo state, `terraform show`, or a sensitive `terraform output` (e.g. `root_password` in `terraform/outputs.tf`) into CI logs. Nothing sensitive is committed to Git by design — the backend is where it actually lives.

---

## Ansible Playbook Discovery

### Critical Rule
**Playbook filename MUST exactly match the VM/LXC hostname.**

- Hostname in Terraform → matches playbook name → automatically discovered by `ansible.sh`
- Pattern: `ansible/playbooks/{hostname}.yml` or `.yaml`
- Examples:
  - VM hostname `docker` → `docker.yml`
  - LXC hostname `dns01` → `dns01.yml`
  - LXC hostname `gitea` → `gitea.yaml`

### Execution Flow
1. Terraform outputs VM/LXC data (including hostname)
2. `ansible/ansible.sh` iterates over VMs
3. Validates `vm_type` is `lxc` or `qemu` — an unknown type is a **failure**, not a skip
4. Looks for matching playbook
5. Skips if not found (recorded in the summary; Talos nodes have none by design, #3)
6. Runs playbook via SSH with root user

### A Failed Host Exits Non-Zero
`ansible.sh` processes **every** guest and then exits `1` if any failed, with a
summary naming each one. It does not stop at the first failure, so one broken
playbook does not hide the state of the other twelve.

Previously each playbook ran as
`... $EXTRA_ARGS || echo "Warning: playbook failed for $HOSTNAME"`, which
printed a warning and exited `0`. **A failed host reported success**, so CI
stayed green and the only signal was a line in the middle of a long log. That
cost three consecutive real failures on the `cockpit_files` role, each caught by
reading logs rather than by CI going red. A guest that cannot be reached (no IP
after 20 tries) or whose SSH key injection fails is a failure too.

Do not reintroduce a `|| echo` on a command whose failure matters. If a
condition is genuinely benign — a Talos guest with no playbook — make it
`record_skip`, not a swallowed error.

### Two Key Patterns

**Validate mode** (dry-run):
```bash
ansible/ansible.sh validate <ssh-key> <vms.json>
```
Adds `--check --diff` to ansible-playbook.

**Provision mode** (apply):
```bash
ansible/ansible.sh provision <ssh-key> <vms.json>
```

---

## Kubernetes & FluxCD

### Namespace Management
Each application gets its own namespace. Namespaces are created by CI/CD workflows:
```bash
kubectl get namespace immich || kubectl create namespace immich
```

If an app manifest references a namespace that doesn't exist, Flux will show status `ClusterServiceVersionNotFound` until the namespace is created.

### Secret Creation Pattern
All secrets are created by the `flux-generate-secrets-and-reconcile.yaml` workflow using:
```bash
kubectl create secret <type> <name> \
  --namespace=<ns> \
  --from-literal=key=value \
  --dry-run=client -o yaml | kubectl apply -f -
```

This pattern is **idempotent** and **upserts** (update-or-create).

**Secrets are NOT committed to Git.** They are injected at runtime via CI/CD secrets.

### Multi-Namespace Secret Propagation
The reconcile workflow copies secrets to multiple namespaces:
- `immich`, `nextcloud`, `unifi-network-application`, `music-assistant`: receive restic-secret, slack-webhook, gitea-registry
- `music-assistant`: uses `hostNetwork: true` pinned to `talos-worker-04` (10.0.4.14) so AirPlay/mDNS/RAOP works; web UI via `music-assistant.mesh.rigsb.net`
- `mongodb`: receives mongodb-auth, unifi-db-secret
- `postgresql`: receives postgresql-auth
- `redis`: receives redis-auth

### Flux Reconciliation
Manual reconcile (useful for debugging):
```bash
flux reconcile kustomization <name> --namespace=flux-system
```

---

## Important Gotchas

### 1. All Four Backup CronJobs Share One NFS Export
`immich-backup`, `music-assistant-backup`, `nextcloud-backup`, and `unifi-backup` each declare their **own** PV, but all four resolve to the **same NFS export** `/mnt/backup` (served by the **`backup` LXC at 10.0.4.8**, not the docker host — an earlier revision of this line said docker and was wrong). Contention is therefore shared, not per-app: one app hammering the export can starve the others even though their PVCs look independent. Backrest's repo PV resolves to the same export too, so it is **five** consumers, not four.

That makes the `backup` guest a single point of failure for the entire cluster's backup capability. Its package layer and NFS export are now managed by the `cockpit_files` Ansible role; its data mount is still host-side on `pve2` and not in git — see `ansible/playbooks/roles/cockpit_files/README.md`.

Consequences when tuning or debugging backups:
- **Keep the schedules staggered.** They are `06:00`, `06:15`, `06:30`, `06:45` UTC (uni, music-assistant, nextcloud, immich) for exactly this reason. Overlapping slots cost real backups: music-assistant lost three consecutive nights (09-27..09-29) with `BackoffLimitExceeded` while sharing `06:30` with nextcloud — both started at exactly `06:30:00`, and `concurrencyPolicy: Forbid` then blocked its own replacement pods.
- **`backoffLimit: 1`, not the default 6.** Kubernetes defaults to 6 retries, which piles six more full re-runs onto an export that is already struggling. One retry absorbs a transient blip; the next nightly run is the real recovery path.
- **`activeDeadlineSeconds` is the only guard against a wedged CronJob.** A hard-mounted NFS hang leaves `restic` blocked forever, the pod never exits, and `Forbid` silently blocks every future run. Deadlines are sized ~2-4x the slowest observed run so a legitimately long backup is never killed: uni 600, music-assistant 900, nextcloud 3600, immich 7200. Keep them loose.
- A deadline kill is terminal — the Job is marked `Failed` with `DeadlineExceeded` and does **not** retry, so that night's backup is lost rather than delayed. That is the intended trade.

### 2. Backrest Is Read-Only by Design
Backrest (`cluster/redcloud/apps/backrest/`) is a **browse-only** UI over the restic repos. It has no plans, no auto-unlock, auto-initialize, or prune/check policies, and the repo NFS is mounted `readOnly: true`. The CronJobs are the sole writers. Do not "fix" a failed backup by adding a Backrest policy or unlock step — change the CronJob or the shared script instead.

Two non-obvious constraints:
- `BACKREST_CONFIG` and `BACKREST_DATA` both live under a **single** mount at `/var/lib/backrest`. Mounting the state PVC twice previously shadowed the config directory.
- The Deployment sets `enableServiceLinks: false` and an explicit `BACKREST_PORT=0.0.0.0:9898`. Without the former, Kubernetes injects `<SVC_NAME>_PORT` env vars that clobber Backrest's own port and it never starts listening.

### 3. Do NOT Configure Talos Nodes with Ansible
Talos Kubernetes control planes and workers are provisioned and configured entirely by Terraform. They are **immutable** and do not have playbooks. The `talos` module handles all OS-level configuration.

If you see a Talos node in the VM list but no matching playbook, that's expected. Skipping it is correct.

### 4. Terraform Backend Init
Every `terraform` workspace requires backend initialization. The CI/CD workflow passes backend config at init time:
```bash
terraform init \
  -backend-config='endpoints={s3="<garage-endpoint>"}' \
  -backend-config="access_key=..." \
  -backend-config="secret_key=..." \
  ...
```

Running `terraform init` locally without backend config will fail or create a `.terraform/` directory for local state. Always use `-backend-config` flags for S3 or provide `backend-config.hcl`.

### 5. Secrets Workflow Timing
The `flux-generate-secrets-and-reconcile.yaml` workflow has a **30-second wait loop** for the `backup-scripts` ConfigMap:
```bash
for i in {1..30}; do
  if kubectl get configmap backup-scripts -n backups &>/dev/null; then
    break
  fi
  sleep 10
done
```

If this times out, the workflow fails silently. Check Flux logs if backup jobs aren't running.

### 6. SSH Key Injection
Ansible SSH keys are injected into VMs via cloud-init on first boot. The `ansible.sh` script retries up to 20 times (5-second intervals) to obtain an IP and SSH into the VM. SSH key injection happens before Ansible runs.

If SSH fails after 20 retries, the playbook is skipped with a warning.

### 7. Verify the File Tree, Not the Docs
This file and `README.md` drift as LXCs are renamed and apps are added or removed. Prefer `ls terraform/*.tf`, `ls ansible/playbooks/`, and `ls cluster/redcloud/apps/` over any prose list. Trust `.gitea/workflows/provision.yml` over the README for backend storage.

### 8. `terraform/talos.tf` Version Pin Has Drifted From the Live Cluster — Deliberately Deferred
`terraform/talos.tf` sets `talos_version = "1.13.4"`, but all six nodes actually run Talos `1.11.0` / Kubernetes `v1.34.0`. This is a known, accepted gap: a future `terraform apply` on `main` would attempt to upgrade every node at once.

Do not "fix" the pin by editing it to `1.11.0` as a side effect of unrelated work, and do not run an apply expecting it to be a no-op. Raising the live cluster requires a deliberate, separately-tested rollout. Check before any Terraform apply that touches `talos.tf`:
```bash
kubectl get nodes -o custom-columns='NAME:.metadata.name,TALOS:.status.nodeInfo.osImage'
```

A rollout of this kind drains nodes, so confirm the PDBs are not holding a drain lock first — see #13.

### 9. AirPlay Receivers Need Reverse UDP (Return Path)
When a client on `192.168.187.0/24` AirPlays to a receiver on `10.0.4.0/24` (MA's AirPlay Receiver on `talos-worker-04`), the receiver must send **return timing/RTP UDP back to the client's ephemeral+6001-6010 ports**. If the router only allows the inbound direction, iOS/macOS "connects" but streams zero audio.

Symptom: MA log shows `AirPlay start failed ... audio feed was not confirmed by <player>` and/or `Source stalled: no audio for 30s` on the intake; stock shairport logs `Sync packet received before we got a timing packet back` repeatedly.

Note: old shairport versions tolerate the lost return path (play unsynced); MA's bundled shairport 4.3.7 does not — so this gotcha only bites modern receivers. Fix is on the Mikrotik: open `10.0.4.0/24 → 192.168.187.0/24` UDP for source ports `6001-6010` + `32768-65535` (plus UDP 319-320 for AirPlay 2 PTP).

### 10. AirPlay Clients Also Need UDP Return Path to the Pod (Reverse of #9)
This bites MA **sending** to legacy AirPlay 1 speakers on `10.0.3.0/24` (e.g. the GGMM M4 "Breakfast Room" speaker at `10.0.3.41`). The speaker will not ack RECORD until it has done its NTP timing-sync handshake, which it sends as UDP `0xd2` packets *to the client's ephemeral timing port*. cliairplay's timing thread must be able to receive those packets. Without the return path, every connect stalls identically at `RECORD` (10s timeout, then `error code=connect_failed detail="RAOP connect failed"`) — in all encryption/`et` combinations, including `--et 0`.

Symptom: raw RAOP client or cliairplay reaches ANNOUNCE 200 + SETUP 200 (gets `server_port`/`control_port`/`timing_port` + `Session: 1`) but RECORD hangs; the device sends zero `0xd2` timing packets to the client's timing port.

Fix on the Mikrotik (confirmed resolving): allow UDP `10.0.3.0/24 → 10.0.4.0/24` on ports `32768-65535` (timing/control/audio ephemeral). The reverse direction `10.0.4.0/24 → 10.0.3.0/24` on `319-320,6000-6009,7000-7999,32768-65535` is already open.

**That `32768-65535` allowance alone is not sufficient — confirmed 2026-10-24.** MA streaming to the Office AirPort Express (`10.0.3.30`) over **AirPlay 2 buffered/PTP** passed setup and pulled audio, then died every time after ~15-20s:
```
ap2_mark_rtsp_dead:706 [AP2] RTSP channel failed during SET_PARAMETER
  rtsp://10.0.4.14/... write after 15003ms: Connection timed out; terminating native session
```
On 2.10.8 the same failure surfaced as `POST /feedback` timing out instead. Audibly: a few seconds of audio, then silence or restart loop. The device's TCP channels to the pod were all ESTABLISHED and only the audio channel had bytes stuck in its send queue, which is what made it look like an MA bug rather than a firewall one.

The missing rule was UDP `10.0.3.0/24 → 10.0.4.14` on **`6001-6010`**. Adding just that made playback smooth immediately. Treat `6001-6010` as required in **both** directions between the client VLAN and `10.0.4.0/24` — §9's fix opened it one way and this is the other.

Corollary: do not reach for an MA version rollback when a device starts dropping sessions after an MA upgrade. 2.10.8 and 2.10.6 fail identically under this rule gap; the 2026-10-24 rollback to 2.10.6 was a dead end and was reverted once the firewall rule landed.

### 11. Parts of This Estate Are NOT Under GitOps
The README's claim that everything is managed via Git is **aspirational, not true today**. Terraform owns the *containers* for all 13 guests, but several things it does not own are load-bearing:

- **The `docker` VM's 3.6T data disk is a USB passthrough device** (`TRAN=usb`, model `Portable`). It is in no Proxmox state file and no Terraform resource, and 14 of 16 live PVs resolve through it. Never "fix" this by adding a `disk` block to `docker.tf` — the module cannot express a USB-passthrough disk, and doing so risks creating a second empty disk at the same mount point.
- **SMB shares are owned by the Cockpit web UI** (`cockpit-file-sharing`) and live in the samba *registry* (`include = registry`), not in any templateable file. Used on `docker` (where they block full rebuildability); `backup` has zero shares defined. NFS exports are owned by that same UI — `cockpit_files` writes **no** exports file and only asserts that the UI's `cockpit-file-sharing.exports` still matches `vars/`, ignoring `-fsid=<uuid>` values, comments and option ordering. Do not "helpfully" add a managed exports file: `exportfs(5)` reads every `*.exports` in the directory, so a second one silently re-exports anything the operator removed in the UI, and the UI's change appears to succeed while doing nothing. The cost of asserting is that a rebuilt host must have its exports recreated in the UI by hand — that is deliberate.
- **`backup.yml` runs `common` + `cockpit_files`; `docker.yml` adds it too.** Both file servers' package layers are now managed. Still hand-built on both: the data mounts (host-side `ntfs-3g` on `pve2` for `backup`, which Terraform does not and cannot express) and the Samba shares on `docker`.
- **The `docker` VM's compose stack used to be manual.** It is now under Ansible (`workloads/docker/`, deployed by the `docker` role), but the secrets it needs (`DOCKER_GITEA_RUNNER_REGISTRATION_TOKEN`, `DOCKER_GARAGE_RPC_SECRET`) must exist in Gitea or the role deliberately skips the `.env` and leaves the live one alone. 10 further compose projects sit dormant under `/mnt/share/projects` and are not managed.
- **Two services in `workloads/docker/docker-compose.yml` are disabled by being commented out, not deleted**: `slskd` (Soulseek not wanted) and `soularr` (only bridges lidarr into slskd). Never "clean up" by deleting those blocks — `docker compose up -d --remove-orphans` deletes the container *and its data* when a service leaves the file, whereas commenting it out leaves it inert. Their state dirs (`slskd/config`, `soularr/data`) still hold real data on the host.
- **`dns01`/`dns02`/`gitea` are community-script installs, updated by hand.** The `community_script` role never runs an update. This is deliberate, not an oversight. `gitea`'s `gitea.mesh.rigsb.net` DNS record is maintained by hand too — there is no `Ingress`/`IngressRoute` for it anywhere in `cluster/redcloud`, and external-dns (which only publishes in-cluster records) does not own it. That record is load-bearing: it backs both the Flux Git remote and the container registry (`gitea.mesh.rigsb.net/eric/...`) the backup jobs pull from.
- **CT 105 (`streamer`) device passthrough is applied by hand, not by Terraform.** Proxmox permits only `root@pam` (password auth) to change LXC `devN` keys (`PVE::LXC::check_ct_modify_config_perm`); API tokens — the identity CI uses — are rejected with HTTP 403. So `terraform/streamer.tf` no longer declares `device_passthrough`, and `modules/lxc` freezes the attribute with `ignore_changes` so an apply never tries to reconcile or remove it. The four Line-In keys (`controlC1`, `pcmC1D1c`, `seq`, `timer`) are set on pve3 with `pct set` or the UI. They are **index-based and the index is not stable**: `snd_usb_audio` and `snd_hda_intel` race in probe order, and on 2026-10-19 a pve3 reboot left the adapter on card 0 and the onboard PCH on card 1, so `pct start` died with `TASK ERROR: Device /dev/snd/pcmC1D1c does not exist` and CT 105 stayed down until the index moved back. pve3 pins the order with `options snd_hda_intel index=0` / `options snd_usb_audio index=1` in `/etc/modprobe.d/99-sound-order.conf`, which is host config like the passthrough itself. Check it after any pve3 reboot: `for c in /sys/class/sound/card*; do echo "${c##*/} -> $(cat "$c/id")"; done` must print `card0 -> PCH` and `card1 -> HLMSC4`. Commands, rationale and verification: `ansible/playbooks/roles/streamer/README.md`.

Everything above was verified against the live hosts on 2026-10-01, but there is
no tool in this repo to re-derive it. SSH in as `eric` and check the specific
claim before trusting it. Never dump a `.env`, `restic_env` or registry file to
the terminal — report key names only.

### 12. Do Not Fix a Data Disk or a Samba Share by "Adding It to Terraform"
Both are one-way doors with live data behind them. Adding a `disk` block for the
USB-passthrough data disk would create a *second* volume rather than adopt the
existing one. Templating Samba shares requires first migrating them out of the
registry, because `include = registry` means the definitions are not in
`smb.conf` at all. The short version is that the correct next step is
*assertion* (fail CI when reality and git disagree), not *adoption* (take
ownership of state you cannot reconstruct).

### 13. PDBs Use `maxUnavailable: 1` Because Every Workload Is a Singleton
Every PDB in the cluster guards a **single replica** — the ten hand-written ones (`apps/*/pdb.yaml`, `db/postgresql/pdb.yaml`, `infra/traefik/base/pdb.yaml`) and the two chart-supplied ones (`mongodb`, `redis-master`). With one replica, `maxUnavailable: 0` computes to **zero allowed disruptions**, so a PDB in that shape does not protect availability at all: it permanently blocks every voluntary eviction and makes `kubectl drain` hang on any node holding the pod. Commit `b6d82b3` changed the hand-written ones from `0` to `1`, matching the two charts, which unblocks drains at the cost of a brief, self-healing blip per app.

Two things not to undo:
- **Do not "tighten" these back to `0`.** On a singleton it is functionally a drain lock, and the only thing it can ever block is maintenance. The one exception is `nextcloud-pdb`, which selects two pods (`nextcloud` + `nextcloud-imaginary`) and so is the only PDB here that actually enforces something.
- A PDB on a single-replica Deployment/StatefulSet does not keep the app up during a rollout. If real availability is wanted, scale to 2+ replicas first; only then does the PDB start meaning anything.

Check before any node rollout that the PDBs still permit disruption:
```bash
kubectl get pdb -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,MAX:.spec.maxUnavailable,ALLOWED:.status.disruptionsAllowed'
```
`ALLOWED` must be `>= 1` on every row, or the drain will stall. `minAvailable: 1` on a singleton is the same trap as `maxUnavailable: 0` — it also computes to zero allowed — so do not "fix" one by swapping it for the other.

### 14. "Resources Declared" Is Not "Resources Applied" — Chart Keys and Stale HelmReleases
Two independent failure modes had **every pod in this cluster running BestEffort** while every gate reported green. Both are silent, and they compound.

**A wrong chart key is dropped, not rejected.** Each chart reads resources from one specific path and ignores the rest:
- `traefik` reads **top-level** `.Values.resources` (`_podtemplate.tpl`) and derives `GOMEMLIMIT` from it. `deployment.resources` renders nothing.
- `immich` does `get .Values "server" | mergeOverwrite $ctx.Values`, which **flattens `server:` onto the root** — so `server.resources` becomes a root `resources` key the chart does not read. It belongs at `controllers.main.containers.main.resources`. (`server.persistence` survived the same flattening only because root `persistence` happens to be valid.)
- `nextcloud` wants top-level `resources` plus `cronjob.sidecar.resources`; `redis` uses `master.resources`.

A pod created with no requests is **BestEffort**, i.e. `Container X was using 8Ki, request is 0`, which makes it the **first** victim of any node pressure. That is exactly what produced 12 evicted traefik pods, under **DiskPressure / ephemeral-storage** — not memory, which is why it looked like a memory problem and wasn't.

**Fixing the YAML is not enough — check the pod, not the status.** After the values were corrected, nextcloud/redis/immich rolled out on their own, but `traefik` did not. Its ConfigMap *was* updated and the kustomization was `True`, yet the HelmRelease reported `Ready: True ... UpgradeSucceeded` while the Deployment still sat at revision 2 from 2026-06-10 (last real deploy 2026-07-08, `Ready` frozen since 2026-08-18). `flux reconcile kustomization` — what `flux-generate-secrets-and-reconcile.yaml` runs — did **not** reach it. Only a direct nudge did:
```bash
kubectl annotate helmrelease traefik -n traefik reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```
It then went chart revision 5 -> 6 and rolled the Deployment 2 -> 3. So after touching any HelmRelease values, verify the rendered pod rather than the condition:
```bash
kubectl get pods -n <ns> -o json | jq -r '.items[]|select(.status.phase=="Running")|"\(.metadata.name) \(.status.qosClass) \(.spec.containers[0].resources)"'
```
`BestEffort` means the values never landed. All twelve workloads (traefik, immich x2, nextcloud x2, redis, six flux controllers) now report `Burstable`.

No CPU limit is set on traefik, nextcloud or immich **on purpose** — all three are bursty, and a memory limit without a CPU limit still yields `Burstable`.

### 15. PodSecurity `baseline` Is the Cluster Default — `hostPath` Is Silently Rejected Outside `kube-system`
This is set by **Talos, not by this repo**. The apiserver is passed `--admission-control-config-file=/system/config/kubernetes/kube-apiserver/admission-control-config.yaml`, a Talos-generated `PodSecurityConfiguration` whose defaults are `enforce: baseline`, `warn: restricted`, `audit: restricted`, with `kube-system` the only exemption. So **every namespace that carries no `pod-security.kubernetes.io/*` label is enforced at `baseline`** — including `traefik`, `nextcloud`, `immich` and the rest. Nothing in `cluster/redcloud/**` sets a cluster-wide default; the only namespaces that opt out are `metallb-system` and `music-assistant` (both `privileged`), plus `kubelet-serving-cert-approver` (`restricted`), while `flux-system` is warn-only.

`baseline` forbids `hostPath` volumes, host namespaces, privileged containers and most capabilities. The failure mode is quiet and *looks like success*: the API object is created and `kubectl apply`/Flux both report `Applied`, but admission rejects every pod, so a DaemonSet sits at `DESIRED 0` (or a Deployment at zero ReplicaSets) forever. The only signal is the event:
```
Error creating: pods "..." is forbidden: violates PodSecurity "baseline:latest": hostPath volumes (volume "...")
```
That is exactly what sank the first fix for the traefik buffer spill (#16): the hostPath `DaemonSet` in #525 was admitted as an object and rejected on every pod, so it never ran. #526 replaced it with a sidecar sharing the chart's own `tmp` emptyDir — no hostPath, no privileged namespace, so `baseline` accepts it. If you genuinely need node-wide access, run the agent in `kube-system` or give a dedicated namespace an explicit `privileged` label; do **not** assume an unlabelled namespace can host a `hostPath`.
```bash
# what each namespace enforces (unlabelled = cluster default = baseline)
kubectl get ns -o custom-columns='NS:.metadata.name,ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce'
# why a workload has no pods
kubectl get events -n <ns> --field-selector reason=FailedCreate | grep -i podsecurity
```

### 16. Traefik's Buffering Middleware Writes Request AND Response Bodies to Node Disk
The `limit-buffering` Middleware (`vulcand/oxy` -> `mailgun/multibuf`) spools any body larger than its ~2 MiB in-memory threshold to a `temp-multibuf-*` file under `/tmp` — which is the chart's `tmp` **emptyDir**, i.e. **node disk**, not something scoped to the pod. It buffers the *response* body too, and orphans are left behind when a transfer aborts (upstream `traefik/traefik#9218`, closed as not reproducible), so they accumulate until the pod is recreated. On 2026-10-16 traefik's two pods held ~8.5 GB of them (3.46 GB on cp-02, 2.49 GB + 2.56 GB on worker-01). cp-01's nodefs is only 7.8 GiB, nodefs pressure evicts the pod with the highest usage-above-request, and that pod is traefik — which is how the estate lost its ingress for 13s (#521).

Two independent bounds, both required:
- **Request side:** `maxRequestBodyBytes: 2147483648` (2 GiB) in `resources/limit-buffering.yaml` (was 10 GB, i.e. effectively no limit). Exceeding it returns `413`. `maxResponseBodyBytes` is deliberately **unset** — capping it would `413` large garage/nextcloud downloads, which is worse than the disk risk.
- **Response side:** the `tmp-sweep` sidecar in `base/traefik-values.yaml` (`deployment.additionalContainers`, `busybox:1.36`, loop `sleep 300`, deletes `temp-multibuf-*` older than 30 min). Unlinking an open file is safe on Linux — the directory entry goes away while the writer keeps the inode alive until it closes.

The middleware is attached to **15 routes** (nextcloud, nutweb, unifi, openspeedtest, novnc and 10 `docker-shared` hosts incl. garage), so "just remove it" is not a free fix. Note also that it carries no `retryExpression` (added in `fed3589`, reverted five minutes later in `2e15dea`), so it buys no retry — only the 413 guard and chunked-encoding normalisation. Full rationale lives in the two files above; keep them in sync if the mechanism changes.

### 17. A Container's `/etc/network/interfaces` Is Rewritten At Every Start — But Stale Stanzas Survive

`pve-container` rewrites this file inside the guest on every container start
(`PVE::LXC::Setup::Debian::setup_network`, which ends in `ct_file_set_contents`).
That is why its inode birth time equals the container start on every boot
(measured 2026-10-19: `backup` 18:22:58, `streamer` 18:47:12) and why it carries
no `# --- BEGIN PVE ---` markers — those belong to `ct_modify_file`, which this
path does not use.

The rewrite is **not** wholesale: a block is regenerated from the container
config only for interfaces named in its `netN` keys. Every other line is
preserved verbatim — comments, blank lines, and `iface ethN ...` stanzas for a
NIC that no longer exists. `auto lo`/`iface lo inet loopback` is prepended when
the file does not already configure it.

Two consequences, learned the hard way on 2026-10-19:

- **A stale stanza survives reboots.** CT 105 (`streamer`) carried
  `auto eth1` / `iface eth1 inet static` / `address 192.168.187.19/24`; CT 101
  (`backup`) still carries an `eth1` block duplicating eth0's address. Neither
  container declares a `net1` (`pct config 105` / `pct config 101` show `net0`
  only) and no file in this repo ever declared a second NIC — so a restart does
  **not** clear them. Only an in-guest edit does, and the next start preserves
  its absence. Check `cat /etc/network/interfaces` against `ls /sys/class/net`
  rather than trusting `pct config`.
- **The symptom is a delayed boot, not a visible error.** `ifup -a` fails on the
  missing device, so `networking.service` and `ifupdown-wait-online.service`
  fail, `network-online.target` activates only after the ifupdown timeout, and
  every unit ordered `After=network-online.target` starts minutes late — CT 105's
  capture client went from ~5 minutes after boot to 2 seconds once the block was
  gone. `systemctl is-system-running` reports `degraded` in the meantime; read
  `systemctl --failed` before assuming whatever runs late is at fault.

Interfaces that *are* in the config are config-owned: put those in Terraform
(`network_interfaces` in `terraform/*.tf`) or `pct set` on the host. The only
LXC keys that cannot be applied by an API token remain the `devN` ones (§11).

### 18. A ConfigMap-Mounted File Patch Goes Stale Silently on an Image Bump
`cluster/redcloud/apps/music-assistant/bandcamp-parsers-patch-configmap.yaml`
mounts a hand-corrected `parsers.py` over `bandcamp_async_api`'s vendored
copy inside the music-assistant image, via `additionalVolumes`/
`additionalMounts` with `subPath` (the chart has no `command`/`lifecycle`/
`initContainers` hook, and the pod has no persistent volume over
`/app/venv`, so any live edit to the container filesystem is wiped on the
next pod recreation — confirmed by watching a hand-patched pod revert
within ~10 minutes).

A `subPath` mount like this does not know whether the thing underneath it
changed. Bumping `helmrelease.yaml`'s `image.tag` silently keeps clobbering
whatever `parsers.py` ships in the new image with this old, 0.2.2-era
patched copy — masking an upstream fix if one landed, or breaking outright
if the new image restructured the file (different methods, different
python version path, etc.). Before bumping the MA image tag, check whether
this patch is still needed and still fits:
```bash
POD=$(kubectl get pods -n music-assistant -l app.kubernetes.io/name=music-assistant -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n music-assistant -- python3 -c \
  "import importlib.metadata as m; print(m.version('bandcamp_async_api'))"
```
If the version changed, diff the new image's pristine `parsers.py` (not
the mounted copy, which is always ours) against the ConfigMap's `data`,
and either drop the ConfigMap + its `additionalVolumes`/`additionalMounts`
entries (if fixed upstream) or re-derive the patch against the new layout.

---

## Common Commands

### Terraform
```bash
cd terraform

# Plan changes (requires backend config)
terraform plan

# Apply changes (used in CI/CD)
terraform apply -auto-approve

# Validate syntax
terraform validate

# Refresh state
terraform refresh

# Output VM data (used by Ansible)
terraform output -json vms
terraform output -raw kubeconfig
terraform output -raw talosconfig
```

### Ansible
```bash
cd ansible

# Validate playbooks (dry-run)
./ansible.sh validate /path/to/ssh_key.pem /path/to/vms.json

# Provision (apply)
./ansible.sh provision /path/to/ssh_key.pem /path/to/vms.json
```

### Kubernetes & FluxCD
```bash
export KUBECONFIG=<path-to-kubeconfig>

# Check cluster status
kubectl get nodes

# View Flux Kustomizations
kubectl get kustomizations -n flux-system

# Manually reconcile an app
flux reconcile kustomization apps --namespace=flux-system

# Check secret status in a namespace
kubectl get secrets -n immich

# Tail logs from a pod
kubectl logs -f deployment/immich-server -n immich

# Describe a Kustomization (for debugging)
kubectl describe kustomization apps -n flux-system
```

---

## File References

- **Primary entry point for infrastructure**: `.gitea/workflows/provision.yml`
- **Ansible entry point**: `ansible/ansible.sh`
- **Flux bootstrap**: `.gitea/workflows/flux-bootstrap.yaml`
- **Secret creation & reconciliation**: `.gitea/workflows/flux-generate-secrets-and-reconcile.yaml`
- **Terraform providers**: `terraform/providers.tf` (defines Proxmox + Talos providers)
- **Terraform backend**: Garage S3 (configured in workflows, not in code)
