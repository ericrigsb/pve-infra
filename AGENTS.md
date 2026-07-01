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
   - Configures non-Kubernetes VMs/LXCs: Docker, Gitea, Pihole, backup, proxy, music server
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
│   ├── docker.tf          # Docker host (legacy apps + NFS)
│   ├── talos.tf           # Kubernetes cluster definition
│   ├── pihole.tf, gitea.tf, backup.tf, proxy.tf, streamer.tf
│   └── providers.tf       # Proxmox + Talos providers
├── ansible/
│   ├── playbooks/
│   │   ├── docker.yml     # Docker host config
│   │   ├── pihole.yaml    # Pihole LXC
│   │   ├── gitea.yaml, backup.yml, proxy.yml, streamer.yml
│   │   └── roles/         # Reusable roles
│   └── ansible.sh         # Entry point for CI/CD
├── cluster/redcloud/
│   ├── apps/              # Application manifests (Immich, Nextcloud, Unifi, etc.)
│   ├── db/                # Database deployments (MongoDB, PostgreSQL, Redis)
│   ├── infra/             # Infrastructure: Traefik, MetalLB, cert-manager, NFS, backups
│   └── flux/              # Flux bootstrap & Kustomizations
└── .gitea/workflows/      # CI/CD automation (Gitea Actions, not GitHub)
    ├── provision.yml      # Terraform + Ansible on main merge
    ├── flux-bootstrap.yaml
    └── flux-generate-secrets-and-reconcile.yaml
```

---

## CI/CD & GitOps Flow

### On Pull Request (before merge)
- **provision.yml**: Terraform validate + plan, Ansible lint
- Runs on `terraform/**` or `ansible/**` changes

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

---

## Ansible Playbook Discovery

### Critical Rule
**Playbook filename MUST exactly match the VM/LXC hostname.**

- Hostname in Terraform → matches playbook name → automatically discovered by `ansible.sh`
- Pattern: `ansible/playbooks/{hostname}.yml` or `.yaml`
- Examples:
  - VM hostname `docker` → `docker.yml`
  - LXC hostname `pihole` → `pihole.yaml`
  - LXC hostname `gitea` → `gitea.yaml`

### Execution Flow
1. Terraform outputs VM/LXC data (including hostname)
2. `ansible/ansible.sh` iterates over VMs
3. Looks for matching playbook
4. Skips if not found (with warning)
5. Runs playbook via SSH with root user

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
- `immich`, `nextcloud`, `unifi-network-application`: receive restic-secret, slack-webhook, gitea-registry
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

### 1. Do NOT Configure Talos Nodes with Ansible
Talos Kubernetes control planes and workers are provisioned and configured entirely by Terraform. They are **immutable** and do not have playbooks. The `talos` module handles all OS-level configuration.

If you see a Talos node in the VM list but no matching playbook, that's expected. Skipping it is correct.

### 2. Terraform Backend Init
Every `terraform` workspace requires backend initialization. The CI/CD workflow passes backend config at init time:
```bash
terraform init \
  -backend-config='endpoints={s3="<garage-endpoint>"}' \
  -backend-config="access_key=..." \
  -backend-config="secret_key=..." \
  ...
```

Running `terraform init` locally without backend config will fail or create a `.terraform/` directory for local state. Always use `-backend-config` flags for S3 or provide `backend-config.hcl`.

### 3. Secrets Workflow Timing
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

### 4. SSH Key Injection
Ansible SSH keys are injected into VMs via cloud-init on first boot. The `ansible.sh` script retries up to 20 times (5-second intervals) to obtain an IP and SSH into the VM. SSH key injection happens before Ansible runs.

If SSH fails after 20 retries, the playbook is skipped with a warning.

### 5. Outdated README
Some documentation may be outdated. Always trust the CI/CD workflow files over prose documentation. For example, verify backend storage in `.gitea/workflows/provision.yml` rather than the README.

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
