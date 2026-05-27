#!/usr/bin/env bash
# =============================================================================
# create_user.sh
# Create a user account on multiple Ubuntu instances over SSH
# =============================================================================
# Usage:
#   ./create_user.sh                          # reads hosts from hosts.txt
#   ./create_user.sh 10.0.0.1 10.0.0.2       # pass hosts as arguments
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIG — edit these as needed
# -----------------------------------------------------------------------------
NEW_USER="edul"                          # Username to create on remote hosts
SSH_USER="ubuntu"                          # User used to connect (must have sudo)
SSH_KEY="${HOME}/.ssh/id_ed25519"          # Private key for connecting
SSH_PORT="22"                              # SSH port
HOSTS_FILE="hosts.txt"                     # Fallback host list (one IP per line)
TIMEOUT=10                                 # SSH connection timeout in seconds
LOG_FILE="create_user.log"                 # Log output file

# New user options (set to "" to skip)
NEW_USER_SHELL="/bin/bash"                 # Login shell
NEW_USER_GROUPS="sudo"                     # Comma-separated extra groups (e.g. "sudo,docker")
NEW_USER_PUBKEY=" "  # Public key to add for new user (set "" to skip)
LOCK_PASSWORD=false              # Lock password login (key-only auth)

# -----------------------------------------------------------------------------
# Colours
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log()     { echo -e "$(date '+%Y-%m-%d %H:%M:%S')  $*" | tee -a "$LOG_FILE"; }
info()    { log "${CYAN}[INFO]${NC}    $*"; }
success() { log "${GREEN}[OK]${NC}      $*"; }
warn()    { log "${YELLOW}[WARN]${NC}    $*"; }
error()   { log "${RED}[ERROR]${NC}   $*"; }

# -----------------------------------------------------------------------------
# Check local dependencies
# -----------------------------------------------------------------------------
check_deps() {
  for cmd in ssh ssh-keygen; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
      exit 1
    fi
  done
}

# -----------------------------------------------------------------------------
# Validate config
# -----------------------------------------------------------------------------
validate_config() {
  if [[ -z "$NEW_USER" ]]; then
    error "NEW_USER is not set. Edit the CONFIG section."
    exit 1
  fi

  if [[ ! -f "$SSH_KEY" ]]; then
    error "SSH private key not found: $SSH_KEY"
    error "Generate one with: ssh-keygen -t ed25519 -f $SSH_KEY"
    exit 1
  fi

  if [[ -n "$NEW_USER_PUBKEY" && ! -f "$NEW_USER_PUBKEY" ]]; then
    warn "Public key not found: $NEW_USER_PUBKEY — skipping key install for new user"
    NEW_USER_PUBKEY=""
  fi
}

# -----------------------------------------------------------------------------
# Run a command on a remote host
# -----------------------------------------------------------------------------
remote() {
  local host="$1"; shift
  ssh \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    -o ConnectTimeout="$TIMEOUT" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    "${SSH_USER}@${host}" "$@"
}

# -----------------------------------------------------------------------------
# Create user on a single host
# -----------------------------------------------------------------------------
create_user_on_host() {
  local host="$1"

  info "Connecting to ${host} ..."

  # Test connectivity first
  if ! remote "$host" "echo connected" &>/dev/null; then
    error "Cannot reach ${host} — skipping"
    return 1
  fi

  # Check if user already exists
  if remote "$host" "id ${NEW_USER}" &>/dev/null 2>&1; then
    warn "User '${NEW_USER}' already exists on ${host} — skipping creation"
  else
    info "Creating user '${NEW_USER}' on ${host} ..."

    # Build useradd command
    local useradd_cmd="sudo useradd -m -s ${NEW_USER_SHELL}"
    [[ -n "$NEW_USER_GROUPS" ]] && useradd_cmd+=" -G ${NEW_USER_GROUPS}"
    useradd_cmd+=" ${NEW_USER}"

    remote "$host" "$useradd_cmd"
    success "User '${NEW_USER}' created on ${host}"
  fi

  # Set up .ssh directory for new user
  info "Setting up .ssh directory for '${NEW_USER}' on ${host} ..."
  remote "$host" "
    sudo mkdir -p /home/${NEW_USER}/.ssh &&
    sudo chmod 700 /home/${NEW_USER}/.ssh &&
    sudo touch /home/${NEW_USER}/.ssh/authorized_keys &&
    sudo chmod 600 /home/${NEW_USER}/.ssh/authorized_keys &&
    sudo chown -R ${NEW_USER}:${NEW_USER} /home/${NEW_USER}/.ssh
  "

  # Copy public key to new user's authorized_keys
  #if [[ -n "$NEW_USER_PUBKEY" ]]; then
   # info "Installing SSH public key for '${NEW_USER}' on ${host} ..."
   # local pubkey
   # pubkey=$(cat "$NEW_USER_PUBKEY")

   # remote "$host" "
   #   echo '${pubkey}' | sudo tee -a /home/${NEW_USER}/.ssh/authorized_keys > /dev/null &&
   #   sudo chown ${NEW_USER}:${NEW_USER} /home/${NEW_USER}/.ssh/authorized_keys
   # "
   # success "SSH key installed for '${NEW_USER}' on ${host}"
  #fi

  # Lock password (key-only auth)
  if [[ "$LOCK_PASSWORD" == true ]]; then
    remote "$host" "sudo passwd -l ${NEW_USER}" &>/dev/null
    info "Password login locked for '${NEW_USER}' on ${host} (key-only)"
  fi

  # Verify user was created successfully
  local uid
  uid=$(remote "$host" "id -u ${NEW_USER} 2>/dev/null" || echo "")
  if [[ -n "$uid" ]]; then
    success "Verified: '${NEW_USER}' (UID=${uid}) exists on ${host}"
    return 0
  else
    error "Verification failed for '${NEW_USER}' on ${host}"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}${CYAN}======================================${NC}"
  echo -e "${BOLD}${CYAN}   Remote User Creation Script        ${NC}"
  echo -e "${BOLD}${CYAN}======================================${NC}"
  echo ""
  echo -e "  New user   : ${BOLD}${NEW_USER}${NC}"
  echo -e "  Shell      : ${NEW_USER_SHELL}"
  echo -e "  Groups     : ${NEW_USER_GROUPS:-none}"
  echo -e "  SSH key    : ${NEW_USER_PUBKEY:-none}"
  echo -e "  Lock passwd: ${LOCK_PASSWORD}"
  echo ""

  check_deps
  validate_config

  # Build host list: CLI args take priority, else read hosts.txt
  local hosts=()
  if [[ $# -gt 0 ]]; then
    hosts=("$@")
  elif [[ -f "$HOSTS_FILE" ]]; then
    info "Reading hosts from $HOSTS_FILE"
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      hosts+=("$line")
    done < "$HOSTS_FILE"
  else
    error "No hosts provided and $HOSTS_FILE not found."
    echo ""
    echo "  Usage:  $0 <host1> <host2> <host3>"
    echo "  Or:     add IPs to hosts.txt (one per line)"
    echo ""
    exit 1
  fi

  if [[ ${#hosts[@]} -eq 0 ]]; then
    error "Host list is empty. Nothing to do."
    exit 1
  fi

  info "Hosts to process: ${#hosts[@]}"
  echo ""

  local passed=0 failed=0 failed_hosts=()

  for host in "${hosts[@]}"; do
    echo -e "${CYAN}--- ${host} ---${NC}"
    if create_user_on_host "$host"; then
      ((passed++))
    else
      ((failed++))
      failed_hosts+=("$host")
    fi
    echo ""
  done

  # Summary
  echo -e "${BOLD}${CYAN}======================================${NC}"
  echo -e "  ${GREEN}Succeeded : ${passed}${NC}"
  if [[ $failed -gt 0 ]]; then
    echo -e "  ${RED}Failed    : ${failed}${NC}"
    for h in "${failed_hosts[@]}"; do
      echo -e "    ${RED}✗ ${h}${NC}"
    done
  else
    echo -e "  Failed    : 0"
  fi
  echo -e "  Log       : ${LOG_FILE}"
  echo -e "${BOLD}${CYAN}======================================${NC}"
  echo ""

  [[ $failed -gt 0 ]] && exit 1 || exit 0
}

main "$@"