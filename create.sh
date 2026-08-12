#!/usr/bin/env bash
# ============================================================================
# Hermes Agent VM — create.sh
# Orchestrator: cleanup gate → pre-flight → terraform → attach → wait →
#               ansible baseline → agent → configure → verify
#
# Usage: ./create.sh [--destroy-first]
# Logs:  logs/create_<timestamp>.log (rotated, keep 20)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/create_$TIMESTAMP.log"
CURRENT_PHASE="init"

# ── Logging helpers ────────────────────────────────────────────────────────
log()  { local level="$1"; shift; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$CURRENT_PHASE] $*" | tee -a "$LOG_FILE"; }
info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
err()  { log "ERROR" "$@"; }

# Error trap: fase + linea + comando
trap 'rc=$?; if [ $rc -ne 0 ]; then err "create.sh failed at phase [$CURRENT_PHASE] line $LINENO (exit $rc)"; err "Re-run ./create.sh — every phase is idempotent. Full log: $LOG_FILE"; fi' ERR

# Log rotation: keep last 20 create logs
ls -t "$LOG_DIR"/create_*.log 2>/dev/null | tail -n +21 | xargs -r rm -f || true

info "create.sh starting — VM 501 (hermes), IP 192.168.1.205"
info "Log: $LOG_FILE"
info "Git: $(git -C "$SCRIPT_DIR" log -1 --format='%h %s' 2>/dev/null || echo 'no git')"

# ── Config ─────────────────────────────────────────────────────────────────
source "$SCRIPT_DIR/configs/runtime.env"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.1.200}"

# gopass pre-flight: verificare che i secret siano leggibili
for secret in bootstrap/proxmox/token-id bootstrap/proxmox/token-secret cluster/github/token infra/ssh-host-keys/hermes-agent/ed25519 infra/hermes-vm/bootstrap-password infra/hermes-vm/hermes-password; do
  if ! gopass show -o "$secret" >/dev/null 2>&1; then
    err "gopass locked or missing: $secret — run 'gopass show $secret' once to warm the cache"
    exit 1
  fi
done
info "gopass secrets: all readable"

# Export env vars for Ansible (never written to disk)
export BOOTSTRAP_PASSWORD="$(gopass show -o infra/hermes-vm/bootstrap-password | tr -d '\r')"
export HERMES_PASSWORD="$(gopass show -o infra/hermes-vm/hermes-password | tr -d '\r')"
export HERMES_HOST_KEY="$(gopass cat infra/ssh-host-keys/hermes-agent/ed25519 2>/dev/null)"  # cat: multi-line key
export PROXMOX_VE_API_TOKEN="$(gopass show -o bootstrap/proxmox/token-id | tr -d "'\r")=$(gopass show -o bootstrap/proxmox/token-secret | tr -d "'\r")"
export PROXMOX_VE_INSECURE=true

# ── PHASE 0: Cleanup gate — IP conflict check ──────────────────────────────
CURRENT_PHASE="phase0-cleanup-gate"
info "Phase 0/8 — cleanup gate (IP $IP_ADDRESS conflict check)"
# Real conflict: IP responds AND our VM doesn't exist (e.g. old CT resurrected).
# If VM 501 exists, it legitimately owns .205 — proceed (idempotent re-run).
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$PROXMOX_HOST" "qm status $VM_ID" >/dev/null 2>&1; then
  info "Phase 0/8 — VM $VM_ID exists (idempotent re-run) ... OK"
elif ping -c1 -W1 "$IP_ADDRESS" >/dev/null 2>&1; then
  err "IP $IP_ADDRESS responds but VM $VM_ID does not exist — foreign host on our IP? Aborting."
  exit 1
else
  info "Phase 0/8 — VM absent, IP free ... OK"
fi

# ── PHASE 1: Pre-flight — cloud image, data disk, gopass ──────────────────
CURRENT_PHASE="phase1-preflight"
info "Phase 1/8 — pre-flight"
cd "$SCRIPT_DIR/terraform"

# Data disk: create only if missing (canonical vm-<VMID>-disk-<N> name)
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$PROXMOX_HOST" "pvesm list $STORAGE_POOL --vmid $VM_ID 2>/dev/null | grep -q '$VOLID'" 2>/dev/null; then
  info "Phase 1/8 — data disk $VOLID: exists"
else
  info "Phase 1/8 — data disk $VOLID: not found, creating..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$PROXMOX_HOST" "pvesm alloc $STORAGE_POOL $VM_ID vm-${VM_ID}-disk-2 ${DATA_DISK_GB}G" | tee -a "$LOG_FILE"
  info "Phase 1/8 — data disk created ($DATA_DISK_GB GB)"
fi
info "Phase 1/8 — pre-flight ... OK"

# ── PHASE 2: Terraform apply ───────────────────────────────────────────────
CURRENT_PHASE="phase2-terraform"
info "Phase 2/8 — terraform apply"
terraform init -input=false >/dev/null 2>&1 || true
terraform plan -var "ssh_public_key=$(cat "${SSH_KEY:-$HOME/.ssh/id_ed25519.pub}")" -out=/tmp/hermes.tfplan 2>&1 | tee -a "$LOG_FILE"
terraform apply -input=false /tmp/hermes.tfplan 2>&1 | tee -a "$LOG_FILE"
info "Phase 2/8 — terraform apply ... OK"

# ── PHASE 3: Attach data disk ──────────────────────────────────────────────
CURRENT_PHASE="phase3-attach-disk"
info "Phase 3/8 — attach data disk $VOLID"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$PROXMOX_HOST" "qm set $VM_ID --virtio1 $VOLID" 2>&1 | tee -a "$LOG_FILE"
info "Phase 3/8 — attach ... OK"

# ── PHASE 4: Wait for SSH ──────────────────────────────────────────────────
CURRENT_PHASE="phase4-wait-ssh"
info "Phase 4/8 — wait for SSH on $IP_ADDRESS:22 (timeout 180s)"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o PasswordAuthentication=no"
wait_ok=0
for i in $(seq 1 36); do
  if ssh $SSH_OPTS -o BatchMode=yes "bootstrap@$IP_ADDRESS" "true" >/dev/null 2>&1; then
    info "Phase 4/8 — SSH ready after ~$((i*5))s"
    wait_ok=1
    break
  fi
  sleep 5
done
if [ "$wait_ok" -ne 1 ]; then
  err "Phase 4/8 — SSH timeout. Check: VM up? cloud-init finished? $LOG_FILE"
  exit 1
fi
info "Phase 4/8 — wait SSH ... OK"

# ── PHASE 5-8: Ansible ─────────────────────────────────────────────────────
cd "$SCRIPT_DIR/ansible"
for pb in hermes-baseline hermes-agent hermes-configure hermes-verify; do
  case "$pb" in
    hermes-baseline)  CURRENT_PHASE="phase5-ansible-baseline" ;;
    hermes-agent)     CURRENT_PHASE="phase6-ansible-agent" ;;
    hermes-configure) CURRENT_PHASE="phase7-ansible-configure" ;;
    hermes-verify)    CURRENT_PHASE="phase8-ansible-verify" ;;
  esac
  info "$CURRENT_PHASE — ansible-playbook $pb.yml"
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini "$pb.yml" 2>&1 | tee -a "$LOG_FILE"
  info "$CURRENT_PHASE — $pb.yml exit 0"
done

info "create.sh COMPLETE — Hermes up at http://$IP_ADDRESS:9119 (dashboard)"
info "LLM provider: configure via dashboard at first access."
exit 0
