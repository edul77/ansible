#!/usr/bin/env bash
# =============================================================================
# copy_ssh_keys.sh
# Copy your SSH public key to one or more Ubuntu hosts using ssh-copy-id
# =============================================================================
# Usage:
#   ./copy_ssh_keys.sh                        # reads hosts from hosts.txt
#   ./copy_ssh_keys.sh 10.0.0.1 10.0.0.2     # pass hosts as arguments
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIG — edit these as needed
# -----------------------------------------------------------------------------
SSH_USER="ubuntu"                        # Remote user
SSH_PORT="22"                            # SSH port
SSH_KEY="${HOME}/.ssh/id_rsa.pub"        # Public key to copy
HOSTS_FILE="hosts.txt"                   # Fallback host list (one IP per line)
TIMEOUT=10                               # Connection timeout in seconds
LOG_FILE="copy_ssh_keys.log"             # Log file

# -----------------------------------------------------------------------------
# Colours
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S')  $*" | tee -a "$LOG_FILE"; }
info()    { log "${CYAN}[INFO]${NC}    $*"; }
success() { log "${GREEN}[OK]${NC}      $*"; }
warn()    { log "${YELLOW}[WARN]${NC}    $*"; }
error()   { log "${RED}[ERROR]${NC}   $*"; }

# -----------------------------------------------------------------------------
# Check dependencies
# -----------------------------------------------------------------------------
check_deps() {
  for cmd in ssh-copy-id ssh-keygen ssh; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
      exit 1
    fi
  done
}

# -----------------------------------------------------------------------------
# Ensure the public key exists; offer to generate one if not
# -----------------------------------------------------------------------------
ensure_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    warn "Public key not found: $SSH_KEY"
    read -rp "Generate a new ED25519 keypair now? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      local key_base="${SSH_KEY%.pub}"
      ssh-keygen -t ed25519 -f "$key_base" -C "${USER}@$(hostname)"
      SSH_KEY="${key_base}.pub"
      success "Keypair generated: $SSH_KEY"
    else
      error "No SSH key available. Exiting."
      exit 1
    fi
  fi
  info "Using public key: $SSH_KEY"
}

# -----------------------------------------------------------------------------
# Copy key to a single host
# -----------------------------------------------------------------------------
copy_key_to_host() {
  local host="$1"
  info "Copying key to ${SSH_USER}@${host}:${SSH_PORT} ..."

  if ssh-copy-id \
      -i "$SSH_KEY" \
      -p "$SSH_PORT" \
      -o ConnectTimeout="$TIMEOUT" \
      -o StrictHostKeyChecking=no \
      "${SSH_USER}@${host}" 2>>"$LOG_FILE"; then
    success "Key copied → ${host}"
    return 0
  else
    error "Failed to copy key → ${host}"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Verify SSH login works after key copy
# -----------------------------------------------------------------------------
verify_host() {
  local host="$1"
  if ssh \
      -i "${SSH_KEY%.pub}" \
      -p "$SSH_PORT" \
      -o ConnectTimeout="$TIMEOUT" \
      -o StrictHostKeyChecking=no \
      -o BatchMode=yes \
      "${SSH_USER}@${host}" "echo ok" &>/dev/null; then
    success "Login verified  → ${host}"
    return 0
  else
    warn "Key copied but login verification failed → ${host} (check manually)"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${CYAN}======================================${NC}"
  echo -e "${CYAN}   SSH Key Distribution Script        ${NC}"
  echo -e "${CYAN}======================================${NC}"
  echo ""

  check_deps
  ensure_key

  # Build host list: CLI args take priority, else read hosts.txt
  local hosts=()
  if [[ $# -gt 0 ]]; then
    hosts=("$@")
  elif [[ -f "$HOSTS_FILE" ]]; then
    info "Reading hosts from $HOSTS_FILE"
    while IFS= read -r line; do
      # Skip blank lines and comments
      [[ -z "$line" || "$line" == \#* ]] && continue
      hosts+=("$line")
    done < "$HOSTS_FILE"
  else
    error "No hosts provided and $HOSTS_FILE not found."
    echo ""
    echo "  Usage:  $0 <host1> <host2> ..."
    echo "  Or:     create a hosts.txt with one IP/hostname per line"
    echo ""
    exit 1
  fi

  if [[ ${#hosts[@]} -eq 0 ]]; then
    error "Host list is empty. Nothing to do."
    exit 1
  fi

  info "Hosts to process: ${#hosts[@]}"
  echo ""

  local passed=0 failed=0

  for host in "${hosts[@]}"; do
    echo -e "${CYAN}--- ${host} ---${NC}"
    if copy_key_to_host "$host"; then
      verify_host "$host" && ((passed++)) || ((passed++))
    else
      ((failed++))
    fi
    echo ""
  done

  # Summary
  echo -e "${CYAN}======================================${NC}"
  echo -e "  ${GREEN}Succeeded: ${passed}${NC}"
  [[ $failed -gt 0 ]] && echo -e "  ${RED}Failed:    ${failed}${NC}" || echo -e "  Failed:    ${failed}"
  echo -e "  Log:       ${LOG_FILE}"
  echo -e "${CYAN}======================================${NC}"
  echo ""

  [[ $failed -gt 0 ]] && exit 1 || exit 0
}

main "$@"
