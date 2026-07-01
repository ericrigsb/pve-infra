#!/usr/bin/env bash
set -euo pipefail

MODE=${1:-provision}
SSHKEY_PATH=${2:?missing SSH private key path}
JSON_FILE=${3:?missing JSON file path}

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
  ROOT_PASSWORD_B64=$(printf '%s' "$ROOT_PASSWORD" | base64 | tr -d '\n')

  if [[ -f "$PLAYBOOK_BASE/${HOSTNAME}.yml" ]]; then
    PLAYBOOK_PATH="$PLAYBOOK_BASE/${HOSTNAME}.yml"
  elif [[ -f "$PLAYBOOK_BASE/${HOSTNAME}.yaml" ]]; then
    PLAYBOOK_PATH="$PLAYBOOK_BASE/${HOSTNAME}.yaml"
  else
    echo "Missing playbook for $HOSTNAME (expected .yml or .yaml in $PLAYBOOK_BASE), skipping"
    echo "-----------------------------"
    continue
  fi

  echo "Processing $VM_TYPE VM '$HOSTNAME' (ID: $VMID) on node '$TARGET_NODE'..."

  IP=""
  for i in {1..20}; do
    IP=""

    if [[ "$VM_TYPE" == "lxc" ]]; then
      IP=$(ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$TARGET_NODE.rigsb.net" \
        "pct exec $VMID -- ip -4 addr show $INTERFACE 2>/dev/null" | \
        grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1) || true

      if [[ -n "$IP" ]]; then
        if ! ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$TARGET_NODE.rigsb.net" \
          "pct exec $VMID -- sh -ceu '
            install -d -m 700 /root/.ssh
            touch /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys
            grep -qxF \"$PUBKEY\" /root/.ssh/authorized_keys || printf \"%s\n\" \"$PUBKEY\" >> /root/.ssh/authorized_keys
            PASS=\$(printf \"%s\" \"$ROOT_PASSWORD_B64\" | base64 -d)
            printf \"root:%s\n\" \"\$PASS\" | chpasswd
          '"; then
          echo "Warning: key/password injection failed for LXC $VMID on $TARGET_NODE; continuing"
        fi
      fi

    elif [[ "$VM_TYPE" == "qemu" ]]; then
      JSON=$(ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$TARGET_NODE.rigsb.net" \
        "qm agent $VMID network-get-interfaces 2>/dev/null") || true

      IP=$(echo "$JSON" | jq -r --arg iface "$INTERFACE" '
        .[]
        | select(.name == $iface)
        | .["ip-addresses"][]?
        | select(.["ip-address-type"] == "ipv4")
        | .["ip-address"]
      ' | head -n1) || true

      if [[ -n "$IP" ]]; then
        injected=false
        for j in {1..10}; do
          if ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$IP" true 2>/dev/null; then
            echo "Injecting SSH key and root password via SSH to $IP..."
            ssh -i "$SSHKEY_PATH" -o StrictHostKeyChecking=no root@"$IP" bash -s <<EOF
mkdir -p /root/.ssh
chmod 700 /root/.ssh
grep -qxF "$PUBKEY" /root/.ssh/authorized_keys || echo "$PUBKEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
PASS=\$(printf '%s' "$ROOT_PASSWORD_B64" | base64 -d)
printf 'root:%s\n' "\$PASS" | chpasswd
EOF
            injected=true
            break
          else
            echo "Waiting for SSH to be available on $IP... attempt $j"
            sleep 5
          fi
        done

        if [[ "$injected" != true ]]; then
          echo "Warning: key/password injection failed for QEMU $VMID ($IP)"
          sleep 5
          continue
        fi
      fi

    else
      echo "Unknown VM_TYPE '$VM_TYPE' (must be 'lxc' or 'qemu')"
      continue
    fi

    if [[ -n "$IP" ]]; then
      echo "Got IP: $IP"
      echo "Running Ansible playbook for $HOSTNAME..."
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i "$IP," \
        -u root \
        --private-key "$SSHKEY_PATH" \
        "$PLAYBOOK_PATH" \
        $EXTRA_ARGS || echo "Warning: playbook failed for $HOSTNAME"
      break
    fi

    echo "Waiting for IP... attempt $i"
    sleep 5
  done

  if [[ -z "$IP" ]]; then
    echo "Failed to obtain IP for $HOSTNAME after 20 tries."
  fi

  echo "-----------------------------"
done