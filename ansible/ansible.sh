#!/usr/bin/env bash
set -euo pipefail

MODE=${1:-provision}
SSHKEY_PATH=$2
JSON_FILE=$3

PLAYBOOK_BASE="ansible/playbooks"
EXTRA_ARGS=""

if [[ "$MODE" == "validate" ]]; then
  EXTRA_ARGS="--check --diff"
fi

mapfile -t VMS < <(jq -c '.[]' "$JSON_FILE")

for vm_json in "${VMS[@]}"; do
  VMID=$(jq -r '.vmid' <<< "$vm_json")
  HOSTNAME=$(jq -r '.hostname' <<< "$vm_json")
  TARGET_NODE=$(jq -r '.target_node' <<< "$vm_json")
  INTERFACE=$(jq -r '.interface' <<< "$vm_json")
  VM_TYPE=$(jq -r '.vm_type' <<< "$vm_json")
  PUBKEY=$(jq -r '.public_key' <<< "$vm_json")
  ROOT_PASSWORD=$(jq -r '.root_password' <<< "$vm_json")

  echo "🔧 Processing $VM_TYPE VM '$HOSTNAME' (ID: $VMID) on node '$TARGET_NODE'..."

  for i in {1..20}; do
    IP=""
    if [[ "$VM_TYPE" == "lxc" ]]; then
      # Get IP address
      IP=$(ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$TARGET_NODE.rigsb.net" \
        "pct exec $VMID -- ip -4 addr show $INTERFACE 2>/dev/null" | \
        grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1) || true

      # Inject SSH key and password
      ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$TARGET_NODE.rigsb.net" \
        "pct exec $VMID -- bash -c '
          mkdir -p /root/.ssh && chmod 700 /root/.ssh
          grep -qxF \"$PUBKEY\" /root/.ssh/authorized_keys || echo \"$PUBKEY\" >> /root/.ssh/authorized_keys
          chmod 600 /root/.ssh/authorized_keys
          echo root:$ROOT_PASSWORD | chpasswd
        '" || true

elif [[ "$VM_TYPE" == "qemu" ]]; then
  # Get IP address via agent
  JSON=$(ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$TARGET_NODE.rigsb.net" \
    "qm agent $VMID network-get-interfaces 2>/dev/null") || true

  IP=$(echo "$JSON" | jq -r --arg iface "$INTERFACE" '
    .[]
    | select(.name == $iface)
    | .["ip-addresses"][]?
    | select(.["ip-address-type"] == "ipv4")
    | .["ip-address"]
  ' | head -n1) || true

  # Wait until we get an IP address using guest agent
  JSON=$(ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$TARGET_NODE.rigsb.net" \
    "qm agent $VMID network-get-interfaces 2>/dev/null") || true

  IP=$(echo "$JSON" | jq -r --arg iface "$INTERFACE" '
    .[]
    | select(.name == $iface)
    | .["ip-addresses"][]?
    | select(.["ip-address-type"] == "ipv4")
    | .["ip-address"]
  ' | head -n1) || true

  # Wait until VM is reachable via SSH and inject key/password
  if [[ -n "$IP" ]]; then
    for j in {1..10}; do
      if ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$IP" true 2>/dev/null; then
        echo "🔐 Injecting SSH key and root password via SSH to $IP..."
        ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$IP" bash -s <<EOF
mkdir -p /root/.ssh
chmod 700 /root/.ssh
grep -qxF "$PUBKEY" /root/.ssh/authorized_keys || echo "$PUBKEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo root:$ROOT_PASSWORD | chpasswd
EOF
        break
      else
        echo "⏳ Waiting for SSH to be available on $IP... attempt $j"
        sleep 5
      fi
    done
  fi

    else
      echo "❌ Unknown VM_TYPE '$VM_TYPE' — must be 'lxc' or 'qemu'"
      continue
    fi

    if [[ -n "$IP" ]]; then
      echo "✅ Got IP: $IP"
      echo "📦 Running Ansible playbook for $HOSTNAME..."

      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i "$IP," \
        -u root \
        --private-key "$SSHKEY_PATH" \
        "$PLAYBOOK_BASE/${HOSTNAME}.yml" \
        $EXTRA_ARGS || echo "⚠️ Warning: Playbook failed for $HOSTNAME"
      break
    fi

    echo "⏳ Waiting for IP... attempt $i"
    sleep 5
  done

  if [[ -z "$IP" ]]; then
    echo "❌ Failed to obtain IP for $HOSTNAME after 20 tries."
  fi

  echo "-----------------------------"
done