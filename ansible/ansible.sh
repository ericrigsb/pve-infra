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

# Failures are collected rather than aborting on the first one. Every host is
# still processed, so a single broken playbook does not hide the state of the
# other twelve -- and the script exits non-zero at the end so CI goes red.
#
# This used to be `... || echo "Warning: playbook failed for $HOSTNAME"`, which
# printed a warning and carried on to a zero exit. A failed host therefore
# reported success. That cost three consecutive real failures on this role
# (per-host vars never loaded, wrong deb path, failed_when inside a loop) that
# each had to be caught by reading CI logs rather than by CI going red.
FAILED_HOSTS=()
FAILED_REASONS=()
SKIPPED_HOSTS=()

record_failure() {
  FAILED_HOSTS+=("$1")
  FAILED_REASONS+=("$2")
  echo "FAILED: $1 -- $2"
}

record_skip() {
  SKIPPED_HOSTS+=("$1")
  echo "Skipped: $1 -- $2"
}

for vm_json in "${VMS[@]}"; do
  VMID=$(jq -r '.vmid' <<< "$vm_json")
  HOSTNAME=$(jq -r '.hostname' <<< "$vm_json")
  TARGET_NODE=$(jq -r '.target_node' <<< "$vm_json")
  INTERFACE=$(jq -r '.interface' <<< "$vm_json")
  VM_TYPE=$(jq -r '.vm_type' <<< "$vm_json")
  PUBKEY=$(jq -r '.public_key' <<< "$vm_json")
  ROOT_PASSWORD=$(jq -r '.root_password' <<< "$vm_json")
  ROOT_PASSWORD_B64=$(printf '%s' "$ROOT_PASSWORD" | base64 | tr -d '\n')

  # Validate vm_type BEFORE looking for a playbook. Otherwise a guest with an
  # unrecognised vm_type and no playbook is reported as a benign "no playbook"
  # skip -- masking a real error in the terraform output behind exit 0.
  case "$VM_TYPE" in
    lxc | qemu) ;;
    *)
      record_failure "$HOSTNAME" "unknown VM_TYPE '$VM_TYPE' (must be 'lxc' or 'qemu')"
      echo "-----------------------------"
      continue
      ;;
  esac

  if [[ -f "$PLAYBOOK_BASE/${HOSTNAME}.yml" ]]; then
    PLAYBOOK_PATH="$PLAYBOOK_BASE/${HOSTNAME}.yml"
  elif [[ -f "$PLAYBOOK_BASE/${HOSTNAME}.yaml" ]]; then
    PLAYBOOK_PATH="$PLAYBOOK_BASE/${HOSTNAME}.yaml"
  else
    # Not a failure: Talos nodes have no playbook by design (AGENTS.md #3), and
    # ansible.sh may also be handed a guest that has not been given one yet.
    # Recorded so it is visible in the summary rather than silently dropped.
    record_skip "$HOSTNAME" "no playbook in $PLAYBOOK_BASE"
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
          record_failure "$HOSTNAME" "SSH key/password injection failed (LXC $VMID on $TARGET_NODE)"
          IP=""
          # Clear the IP so the retry loop below does not proceed to run a
          # playbook against a host we could not authenticate to.
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
          record_failure "$HOSTNAME" "SSH key/password injection failed (QEMU $VMID at $IP)"
          IP=""
        fi
      fi

    else
      # Unreachable: vm_type is validated above, so this branch cannot be hit.
      record_failure "$HOSTNAME" "internal error: unhandled VM_TYPE '$VM_TYPE'"
      echo "-----------------------------"
      continue
    fi

    if [[ -n "$IP" ]]; then
      echo "Got IP: $IP"
      echo "Running Ansible playbook for $HOSTNAME..."
      set +e
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i "$IP," \
        -u root \
        --private-key "$SSHKEY_PATH" \
        "$PLAYBOOK_PATH" \
        $EXTRA_ARGS
      rc=$?
      set -e
      if [[ $rc -ne 0 ]]; then
        # Recorded, not fatal to the run: every other host is still processed
        # and the summary below exits non-zero if anything failed. This is the
        # line that used to swallow the failure.
        record_failure "$HOSTNAME" "playbook $PLAYBOOK_PATH exited $rc"
      fi
      break
    fi

    echo "Waiting for IP... attempt $i"
    sleep 5
  done

  if [[ -z "$IP" ]]; then
    # Only record this if the host is not already recorded: an injection
    # failure clears IP deliberately, so this would otherwise double-count the
    # same host with a less useful reason and mask the real one.
    if [[ " ${FAILED_HOSTS[*]:-} " != *" $HOSTNAME "* ]]; then
      record_failure "$HOSTNAME" "could not obtain an IP after $i tries"
    fi
  fi

  echo "-----------------------------"
done

echo "======================================"
if [[ ${#SKIPPED_HOSTS[@]} -gt 0 ]]; then
  echo "Skipped (${#SKIPPED_HOSTS[@]}): ${SKIPPED_HOSTS[*]}"
fi

if [[ ${#FAILED_HOSTS[@]} -eq 0 ]]; then
  echo "Ansible: all ${#VMS[@]} guests completed successfully."
  echo "======================================"
  exit 0
fi

echo "Ansible FAILED on ${#FAILED_HOSTS[@]} of ${#VMS[@]} guests:"
i=0
while [[ $i -lt ${#FAILED_HOSTS[@]} ]]; do
  echo "  - ${FAILED_HOSTS[$i]}: ${FAILED_REASONS[$i]}"
  i=$((i + 1))
done
echo "======================================"
exit 1