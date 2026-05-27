#!/usr/bin/env bash
# Creates a user account on multiple Ubuntu instances via SSH password auth

# -----------------------------------------------------------------------------
# CONFIG
# -----------------------------------------------------------------------------
HOSTS=(
  "10.200.11.224"
  "10.200.9.165"
  "10.200.8.101"
)

SSH_USER="ubuntu"    # User to connect as (needs sudo)
NEW_USER="edul"    # User to create on each host

# -----------------------------------------------------------------------------
# Check sshpass is installed
# -----------------------------------------------------------------------------
if ! command -v sshpass &>/dev/null; then
  echo "sshpass is required. Install it with: sudo apt install sshpass"
  exit 1
fi

# -----------------------------------------------------------------------------
# Prompt for passwords once
# -----------------------------------------------------------------------------
read -rsp "SSH password for '${SSH_USER}': " SSH_PASS; echo
read -rsp "Password to set for new user '${NEW_USER}': " NEW_PASS; echo
read -rsp "Confirm password for '${NEW_USER}': " NEW_PASS_CONFIRM; echo

if [[ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]]; then
  echo "Passwords do not match. Exiting."
  exit 1
fi

export SSHPASS="$SSH_PASS"

# -----------------------------------------------------------------------------
# Loop through hosts and create user
# -----------------------------------------------------------------------------
for HOST in "${HOSTS[@]}"; do
  echo ""
  echo "--- $HOST ---"

  sshpass -e ssh \
    -o StrictHostKeyChecking=no \
    -o PasswordAuthentication=yes \
    "${SSH_USER}@${HOST}" \
    "id ${NEW_USER} &>/dev/null && echo 'User already exists — skipping' || (
      sudo useradd -m -s /bin/bash -G sudo ${NEW_USER} &&
      echo '${NEW_USER}:${NEW_PASS}' | sudo chpasswd &&
      echo 'User created successfully'
    )"

  [[ $? -eq 0 ]] && echo "Done: $HOST" || echo "Failed: $HOST"
done

unset SSHPASS SSH_PASS NEW_PASS NEW_PASS_CONFIRM
echo ""
echo "Finished."