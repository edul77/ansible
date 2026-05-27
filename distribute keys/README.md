# Ansible: Distribute SSH Keys to Ubuntu Instances

## Files

| File | Purpose |
|------|---------|
| `distribute_ssh_keys.yml` | Main playbook |
| `inventory.ini` | Host definitions |
| `ansible.cfg` | Ansible configuration |

---

## Quick Start

### 1. Prerequisites

```bash
pip install ansible
ansible-galaxy collection install ansible.posix   # provides authorized_key module
```

### 2. Edit inventory.ini

Add your Ubuntu server IPs/hostnames:

```ini
[ubuntu_servers]
web01 ansible_host=10.0.0.10
web02 ansible_host=10.0.0.11
```

### 3. Run the playbook

```bash
# Add your local ~/.ssh/id_rsa.pub to all servers
ansible-playbook -i inventory.ini distribute_ssh_keys.yml

# Add keys for a different user
ansible-playbook -i inventory.ini distribute_ssh_keys.yml -e "target_user=deploy"

# Only add keys (skip other tasks)
ansible-playbook -i inventory.ini distribute_ssh_keys.yml --tags add

# Also harden sshd_config (disable password auth, etc.)
ansible-playbook -i inventory.ini distribute_ssh_keys.yml -e "harden_sshd=true"

# Dry run (check mode — no changes made)
ansible-playbook -i inventory.ini distribute_ssh_keys.yml --check

# Verbose output
ansible-playbook -i inventory.ini distribute_ssh_keys.yml -v
```

---

## Adding Multiple Keys

Edit the `ssh_keys` list in the playbook:

```yaml
ssh_keys:
  - comment: "Admin key"
    key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
    state: present

  - comment: "CI/CD key"
    key: "ssh-ed25519 AAAAC3Nza... ci@pipeline"
    state: present

  - comment: "Revoked developer"
    key: "ssh-rsa AAAAB3Nza... old-dev@example.com"
    state: absent        # This key will be REMOVED
```

---

## Tags Reference

| Tag | What it does |
|-----|-------------|
| `add` | Add keys + ensure .ssh setup |
| `remove` | Remove keys marked `state: absent` |
| `harden` | Apply sshd_config hardening (needs `-e "harden_sshd=true"`) |
| `setup` | Only ensure directory/file structure |
| `always` | Runs regardless of tag filter |

---

## Notes

- The playbook uses `exclusive: false` — it **adds** keys without removing others.  
  Set `exclusive: true` to **replace all** keys (use with caution).
- Password authentication is only disabled if you set `harden_sshd: true`.
- A backup of `sshd_config` is created automatically before any changes.
