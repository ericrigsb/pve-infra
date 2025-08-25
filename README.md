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

- **Ingress and load balancing** with [Traefik](https://traefik.io/) and [MetalLB](https://metallb.universe.tf/)
- **Automated TLS certificates** via [cert-manager](https://cert-manager.io/) and Let's Encrypt (Cloudflare DNS-01)
- **Database management** with MongoDB, PostgreSQL, and Redis
- **Backup infrastructure** with automated backup jobs and Restic
- **App deployment** via Kubernetes manifests and Kustomizerastructure as Code (IaC) for deploying and managing services on a Proxmox Virtual Environment (PVE) cluster, using **GitOps** and **CI/CD automation**.  
**All provisioning, configuration, and deployment is managed via Git and automated CI/CD workflows—manual execution is not required or recommended.**

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
│       ├── apps/      # Kubernetes app manifests (Immich, Nextcloud, etc.)
│       ├── db/        # Database deployments (MongoDB, PostgreSQL, Redis)
│       ├── flux/      # Flux Kustomizations and GitRepository
│       └── infra/     # Infra components: traefik, metallb, cert-manager, nfs, backups
├── terraform/         # Terraform modules and configs for PVE, Talos, etc.
└── .gitea/workflows/  # Gitea Actions CI/CD workflows
```

---

## GitOps & CI/CD Workflow

**All changes are made via Git.**  
When you push to the repository:

1. **CI/CD workflows** (in `.gitea/workflows/` or your GitHub Actions) are triggered automatically.
2. **Terraform** plans and applies infrastructure changes to Proxmox and Talos.
3. **Ansible** configures VMs/LXCs as needed.
4. **Kubernetes manifests** (apps, infra, secrets) are applied or updated.
5. **FluxCD** continuously reconciles the cluster state with the Git repository.
6. **cert-manager** and other controllers handle certificates and service automation.

**Manual execution of Terraform, Ansible, or kubectl is not required.**  
All provisioning, configuration, and deployment is handled by CI/CD and GitOps.

---

## Required Variables & Secrets

All sensitive variables and secrets must be provided as **repository or CI/CD secrets** (never committed to Git).  
These are injected into workflows at runtime.

### **Terraform Backend (MinIO/S3)**

- `MINIO_ENDPOINT_URL` — MinIO S3 endpoint URL (repository variable)
- `MINIO_ACCESS_KEY` — MinIO access key 
- `MINIO_ACCESS_KEY_SECRET` — MinIO secret key

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
| `MINIO_ENDPOINT_URL`          | Variable | MinIO S3 endpoint URL                        |
| `MINIO_ACCESS_KEY`            | Secret   | MinIO access key                             |
| `MINIO_ACCESS_KEY_SECRET`     | Secret   | MinIO secret key                             |
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
- Pihole
- Backup server
- Reverse proxy/VPN
- Music server
- Gitea server

### Ansible-Managed Configuration

Ansible handles OS-level configuration for VMs and LXC containers:
- Docker installation and configuration
- Backup system setup
- Proxy/VPN configuration
- Music server setup
- Common system configurations (users, SSH, security)

### Current Applications

**Kubernetes Applications:**
The cluster includes the following applications:
- **Photo Management**: Immich 
- **Cloud Storage**: Nextcloud
- **Network Management**: Unifi Network Application
- **Monitoring**: Uptime Kuma
- **Notifications**: Mailrise
- **UPS Monitoring**: NUT Web
- **Speed Testing**: OpenSpeedTest

**External Services (LXC/VM):**
These services run outside Kubernetes but are integrated via ingress for external access:
- **DNS**: Pihole (web interface ONLY)
- **Git Hosting**: Gitea
- **Switch Management**: Switch interface
- **Router Management**: Router interface
- **Modem Management**: Modem interface

These services operate entirely outside of the Kubernetes cluster:
- **Container Platform and File Services**: Docker host for legacy applications and NFS exports for applications
- **Backup System**: Automated backup infrastructure
- **Media Server**: Music streaming services

---

## Tips

- **Wildcard TLS**: Use cert-manager’s Ingress annotation for per-app cert automation, or copy wildcard secrets to each namespace as needed.
- **GitOps**: All cluster/app changes should be made via Git and Flux will reconcile automatically.
- **Secrets**: Sensitive data (API tokens, SSH keys) should be managed via CI/CD secrets and not committed to Git.

---

## License

MIT