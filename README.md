# 🚨 Important Notice

This repository is published as a **reference implementation** for educational purposes. Before using this code:

1. **Replace all IP addresses, domain names, and hostnames** with your own
2. **Configure secrets and variables** through your CI/CD system repository settings
3. **Update Terraform variables** for your specific Proxmox environment  
4. **Review and customize** all application configurations for your needs
5. **Ensure proper security practices** are followed in your environment

All sensitive configuration should be managed through CI/CD variables and repository secrets, not committed to the repository.

---

# pve-infra

Infrastructure as Code (IaC) for deploying and managing services on a Proxmox Virtual Environment (PVE) cluster, using **GitOps** and **CI/CD automation**.

**Features:**
- **Ingress and load balancing** with [Traefik](https://traefik.io/) and [MetalLB](https://metallb.universe.tf/)
- **Automated TLS certificates** via [cert-manager](https://cert-manager.io/) and Let's Encrypt (Cloudflare DNS-01)
- **Database management** with MongoDB, PostgreSQL, and Redis
- **Backup infrastructure** with automated backup jobs and Restic, plus a read-only Backrest web UI
- **App deployment** via Kubernetes manifests and Kustomize

**Provisioning, configuration, and deployment flow through Git and automated CI/CD workflows—manual execution is not recommended. A few load-bearing pieces are still hand-managed (see `AGENTS.md` #11).**

> **Two separate DNS systems are in play, and they are easy to confuse.**
> - **Public DNS (`rigsb.net`)** — Cloudflare, used by cert-manager for ACME DNS-01 challenges.
> - **Internal DNS (`mesh.rigsb.net`)** — Technitium on the `dns01` LXC. external-dns publishes
>   in-cluster records here over **RFC2136** (`cluster/redcloud/infra/external-dns/`), not via Cloudflare.
>
> cert-manager still uses the Cloudflare solver; only `*.mesh.rigsb.net` names are pushed to Technitium.

---

## Features

- **Proxmox VM and LXC provisioning** with [Terraform](https://www.terraform.io/) (automated via CI/CD)
- **Automated OS configuration** with [Ansible](https://www.ansible.com/) (via CI/CD)
- **Kubernetes cluster management** using [Talos Linux](https://www.talos.dev/)
- **GitOps application delivery** with [FluxCD](https://fluxcd.io/)
- **Ingress and load balancing** with [Traefik](https://traefik.io/) and [MetalLB](https://metallb.universe.tf/)
- **Automated TLS certificates** via [cert-manager](https://cert-manager.io/) and Let’s Encrypt (Cloudflare DNS-01)
- **App deployment** via Kubernetes manifests and Kustomize

---

## Directory Structure

```
.
├── ansible/           # Ansible playbooks and roles for VM/LXC configuration
├── cluster/
│   └── redcloud/
│       ├── apps/      # Kubernetes app manifests (Immich, Nextcloud, Backrest, etc.)
│       ├── db/        # Database deployments (MongoDB, PostgreSQL, Redis)
│       ├── flux/      # Flux Kustomizations and GitRepository
│       └── infra/     # Infra components: traefik, metallb, cert-manager, external-dns, backups
├── terraform/         # Terraform modules and configs for PVE, Talos, etc.
└── .gitea/workflows/  # Gitea Actions CI/CD workflows
```

> Documentation can drift as LXCs are renamed and apps change. Verify with
> `ls terraform/*.tf`, `ls ansible/playbooks/`, and `ls cluster/redcloud/apps/`
> rather than trusting the lists above.

---

## GitOps & CI/CD Workflow

**All changes are made via Git.**  
When you push to the repository:

1. **CI/CD workflows** (in `.gitea/workflows/` via Gitea Actions) are triggered automatically.
2. **Terraform** plans and applies infrastructure changes to Proxmox and Talos.
3. **Ansible** configures VMs/LXCs as needed.
4. **Kubernetes manifests** (apps, infra, secrets) are applied or updated.
5. **FluxCD** continuously reconciles the cluster state with the Git repository.
6. **cert-manager** and other controllers handle certificates and service automation.

**Terraform, Ansible, and Kubernetes changes belong in Git.**
CI/CD workflows and FluxCD apply them, so manual `terraform apply`, `ansible-playbook`, or `kubectl` is not required for anything tracked here. The exception is the handful of load-bearing pieces that are deliberately *not* under Git — the docker host's USB-passthrough data disk, the Samba/NFS exports owned by the Cockpit UI, CT 105 device passthrough, and the `dns01`/`dns02`/`gitea` community-script installs. See `AGENTS.md` #11 before assuming a rebuild is fully scripted.

---

## Required Variables & Secrets

All sensitive variables and secrets must be provided as **repository or CI/CD secrets** (never committed to Git).  
These are injected into workflows at runtime.

### **Terraform Backend (Garage S3)**

- `GARAGE_ENDPOINT_URL` — Garage S3 endpoint URL (repository variable)
- `GARAGE_ACCESS_KEY` — Garage access key 
- `GARAGE_ACCESS_KEY_SECRET` — Garage secret key

### **Proxmox (Terraform)**

- `PM_API_URL` — Proxmox API endpoint (repository variable)
- `PM_API_TOKEN_ID` — Proxmox API token ID
- `PM_API_TOKEN_SECRET` — Proxmox API token secret
- `GUEST_ROOT_PASSWORD` — VM root password
- `PVE_INFRA_SSH_KEY` — SSH private key for provisioning
- `PVE_INFRA_SSH_PUBLIC_KEY` — SSH public key for provisioning
- `GUEST_USER` — Guest user name (repository variable)
- `GUEST_USER_PASSWORD` — Guest user password
- `GUEST_USER_PUBLIC_KEY` — Guest user SSH public key
- `NORDVPN_AUTH_TOKEN` — NordVPN authentication token

### **Kubernetes & Flux**

- `KUBECONFIG` — Base64-encoded kubeconfig for cluster access
- `GIT_REPO_URL` — URL of your GitOps repository (repository variable)
- `BOOTSTRAP_PATH` — Path for Flux bootstrap (repository variable)  
- `FLUX_REPO_HOST` — Git repository host for SSH (repository variable)
- `FLUX_SSH_PRIVATE_KEY` — Base64-encoded SSH private key for Flux Git access

### **Certificate Management**

- `CLOUDFLARE_API_TOKEN` — Cloudflare API token for DNS-01 ACME challenges

### **Application Secrets**

- `MAILRISE_SLACK_API_URL` — Slack webhook URL for notifications
- `MONGODB_ROOT_PASSWORD` — MongoDB root password
- `MONGODB_PASSWORDS` — MongoDB user passwords
- `UNIFI_DB_PASSWORD` — UniFi database password
- `POSTGRES_SUPERUSER_PASSWORD` — PostgreSQL superuser password
- `REDIS_PASSWORD` — Redis password
- `NEXTCLOUD_ADMIN_PASSWORD` — Nextcloud admin password
- `RESTIC_REPO_PASSWORD` — Restic backup repository password
- `REGISTRY_USER` — Container registry username
- `REGISTRY_PASSWORD` — Container registry password
- `NUT_USER` — Network UPS Tools username
- `NUT_PASSWORD` — Network UPS Tools password
- `BACKREST_ADMIN_BCRYPT` — Backrest UI admin password as a bcrypt hash (see note below)
- `TECHNITIUM_TSIG_KEYNAME` — TSIG key name for RFC2136 zone transfers to Technitium
- `TECHNITIUM_TSIG_SECRET` — TSIG secret for RFC2136 zone transfers to Technitium

> **`BACKREST_ADMIN_BCRYPT` is stored base64-encoded.** Backrest expects
> `passwordBcrypt` in its config to be base64 of the 60-byte bcrypt hash, and the
> Deployment's init container encodes the raw `$2y$...` value on every start. Commit
> the raw bcrypt string to the Gitea secret; never commit the hash itself to Git.

### **CI/CD Secret Table**

| Name                          | Type     | Purpose                                      |
|-------------------------------|----------|----------------------------------------------|
| `PM_API_URL`                  | Variable | Proxmox API endpoint                         |
| `PM_API_TOKEN_ID`             | Secret   | Proxmox API token ID                         |
| `PM_API_TOKEN_SECRET`         | Secret   | Proxmox API token secret                     |
| `GUEST_ROOT_PASSWORD`         | Secret   | VM root password                             |
| `PVE_INFRA_SSH_KEY`           | Secret   | SSH private key for provisioning            |
| `PVE_INFRA_SSH_PUBLIC_KEY`    | Secret   | SSH public key for provisioning             |
| `GUEST_USER`                  | Variable | Guest user name                              |
| `GUEST_USER_PASSWORD`         | Secret   | Guest user password                          |
| `GUEST_USER_PUBLIC_KEY`       | Secret   | Guest user SSH public key                    |
| `NORDVPN_AUTH_TOKEN`          | Secret   | NordVPN authentication token                 |
| `GARAGE_ENDPOINT_URL`         | Variable | Garage S3 endpoint URL                       |
| `GARAGE_ACCESS_KEY`           | Secret   | Garage access key                            |
| `GARAGE_ACCESS_KEY_SECRET`    | Secret   | Garage secret key                            |
| `KUBECONFIG`                  | Secret   | Base64-encoded kubeconfig for cluster access|
| `GIT_REPO_URL`                | Variable | GitOps repo URL for Flux                     |
| `BOOTSTRAP_PATH`              | Variable | Path for Flux bootstrap                      |
| `FLUX_REPO_HOST`              | Variable | Git repository host for SSH                  |
| `FLUX_SSH_PRIVATE_KEY`        | Secret   | Base64-encoded SSH key for Flux Git access  |
| `CLOUDFLARE_API_TOKEN`        | Secret   | Cloudflare API token for DNS-01 ACME        |
| `MAILRISE_SLACK_API_URL`      | Secret   | Slack webhook URL for notifications         |
| `MONGODB_ROOT_PASSWORD`       | Secret   | MongoDB root password                        |
| `MONGODB_PASSWORDS`           | Secret   | MongoDB user passwords                       |
| `UNIFI_DB_PASSWORD`           | Secret   | UniFi database password                      |
| `POSTGRES_SUPERUSER_PASSWORD` | Secret   | PostgreSQL superuser password                |
| `REDIS_PASSWORD`              | Secret   | Redis password                               |
| `NEXTCLOUD_ADMIN_PASSWORD`    | Secret   | Nextcloud admin password                     |
| `RESTIC_REPO_PASSWORD`        | Secret   | Restic backup repository password           |
| `REGISTRY_USER`               | Secret   | Container registry username                  |
| `REGISTRY_PASSWORD`           | Secret   | Container registry password                  |
| `NUT_USER`                    | Secret   | Network UPS Tools username                   |
| `NUT_PASSWORD`                | Secret   | Network UPS Tools password                   |
| `BACKREST_ADMIN_BCRYPT`       | Secret   | Backrest admin bcrypt hash (raw, not b64)    |
| `TECHNITIUM_TSIG_KEYNAME`     | Secret   | TSIG key name for RFC2136 zone transfers     |
| `TECHNITIUM_TSIG_SECRET`      | Secret   | TSIG secret for RFC2136 zone transfers       |

---

## Example: Automated App Deployment

When you add or update an app manifest (e.g., in `cluster/redcloud/apps/immich/` or `cluster/redcloud/apps/nextcloud/`):

- The change is pushed to Git.
- CI/CD workflow applies the manifest.
- FluxCD detects the change and reconciles the cluster.
- cert-manager provisions TLS certificates automatically (using Ingress annotations).
- Traefik and MetalLB expose the service.

**No manual steps are required.**

## Infrastructure Components

### Terraform-Managed Infrastructure

Terraform provisions and manages the following Proxmox infrastructure:

**Virtual Machines:**
- Docker host (also handles file services)
- Talos Kubernetes control planes and workers

**LXC Containers:**
- DNS/adblock servers (dns01, dns02 — replaced Pihole in #457)
- Backup server
- Music server / streamer
- Gitea server
- Sendspin BT bridge (btbridge, privileged with USB passthrough)

### Ansible-Managed Configuration

Ansible handles OS-level configuration for VMs and LXC containers:
- Docker installation and configuration
- Backup system setup
- DNS and adblocking services
- Music server / streamer setup
- BT bridge setup
- Common system configurations (users, SSH, security)

### Current Applications

**Kubernetes Applications:**
The cluster includes the following applications:
- **Photo Management**: Immich
- **Cloud Storage**: Nextcloud
- **Network Management**: Unifi Network Application
- **Audio / Music**: Music Assistant
- **Backup UI**: Backrest (read-only browsable view of the restic repos)
- **Notifications**: Mailrise
- **UPS Monitoring**: NUT Web
- **Speed Testing**: OpenSpeedTest
- **External Service Ingress**: docker-shared (publishes the docker-host services below into the cluster via Traefik)
- **Remote Desktop**: noVNC (novnc-workmac)

**External Services (LXC/VM):**
These services run outside Kubernetes but are integrated via ingress for external access:
- **DNS**: DNS/adblock web interfaces (dns01, dns02)
- **Object Storage (S3)**: Garage (also the Terraform state backend)
- **Status Dashboard**: status page
- **Music Management**: Lidarr
- **Soulseek**: slskd / soularr (both disabled in the docker compose; ingress routes remain)
- **Switch Management**: Switch interface
- **Router Management**: Router interface
- **Modem Management**: Modem interface
- **Bluetooth Audio**: Sendspin BT bridge (btbridge)

These services operate entirely outside of the Kubernetes cluster:
- **Git Hosting**: Gitea (separate LXC at `gitea.mesh.rigsb.net`; its DNS record is maintained by hand, not via external-dns or Traefik — it is also the Flux Git remote and container registry)
- **Container Platform and File Services**: Docker host for legacy applications and NFS exports for applications
- **Backup System**: Automated backup infrastructure (restic repos on shared NFS; Backrest provides a read-only UI)
- **Media Server**: Music streaming services

---

## Tips

- **Wildcard TLS**: Use cert-manager’s Ingress annotation for per-app cert automation, or copy wildcard secrets to each namespace as needed.
- **GitOps**: All cluster/app changes should be made via Git and Flux will reconcile automatically.
- **Secrets**: Sensitive data (API tokens, SSH keys) should be managed via CI/CD secrets and not committed to Git.

---

## License

MIT