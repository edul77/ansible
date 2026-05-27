#!/bin/bash
# Copies your SSH public key to multiple Ubuntu servers using password auth

# -----------------------------------------------------------------------------
# CONFIG
# -----------------------------------------------------------------------------
HOSTS=(
  "10.200.11.224"
  "10.200.9.165"
  "10.200.8.101"
)

SSH_USER="ubuntu"                    # User to connect as
SSH_PUBKEY="$HOME/.ssh/edul.pub"  # Public key to copy

# -----------------------------------------------------------------------------
# Check sshpass is installed
# -----------------------------------------------------------------------------
if ! command -v sshpass &>/dev/null; then
  echo "sshpass is required. Install it with: sudo apt install sshpass"
  exit 1
fi

# Check public key exists
if [[ ! -f "$SSH_PUBKEY" ]]; then
  echo "Public key not found: $SSH_PUBKEY"
  echo "Generate one with: ssh-keygen -t ed25519"
  exit 1
fi

# -----------------------------------------------------------------------------
# Prompt for password once
# -----------------------------------------------------------------------------
read -rsp "SSH password for '${SSH_USER}': " SSH_PASS; echo
export SSHPASS="$SSH_PASS"

# -----------------------------------------------------------------------------
# Loop through hosts and copy key
# -----------------------------------------------------------------------------
for HOST in "${HOSTS[@]}"; do
  echo ""
  echo "--- $HOST ---"

  sshpass -e ssh-copy-id \
    -i "$SSH_PUBKEY" \
    -o StrictHostKeyChecking=no \
    "${SSH_USER}@${HOST}"

  [[ $? -eq 0 ]] && echo "Done: $HOST" || echo "Failed: $HOST"
done

unset SSHPASS SSH_PASS
echo ""
echo "Finished."