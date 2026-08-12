#!/usr/bin/env bash
# ============================================================================
# Hermes Agent VM — destroy.sh
# Safe destroy: unlink data disk (preserved in local-lvm) → terraform destroy
#
# Usage: ./destroy.sh
# Logs:  logs/destroy_<timestamp>.log (rotated, keep 20)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/destroy_$TIMESTAMP.log"
CURRENT_PHASE="init"

log()  { local level="$1"; shift; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$CURRENT_PHASE] $*" | tee -a "$LOG_FILE"; }
info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
err()  { log "ERROR" "$@"; }

trap 'rc=$?; if [ $rc -ne 0 ]; then err "destroy.sh failed at phase [$CURRENT_PHASE] line $LINENO (exit $rc)"; err "Full log: $LOG_FILE"; fi' ERR

ls -t "$LOG_DIR"/destroy_*.log 2>/dev/null | tail -n +21 | xargs -r rm -f

source "$SCRIPT_DIR/configs/runtime.env"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.1.200}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

info "destroy.sh starting — VM $VM_ID (hermes-agent), IP $IP_ADDRESS"
info "Log: $LOG_FILE"

# gopass pre-flight
for secret in bootstrap/proxmox/token-id bootstrap/proxmox/token-secret; do
  if ! gopass show -o "$secret" >/dev/null 2>&1; then
    err "gopass locked or missing: $secret"
    exit 1
  fi
done
export PROXMOX_VE_API_TOKEN="$(gopass show -o bootstrap/proxmox/token-id | tr -d "'\r")=$(gopass show -o bootstrap/proxmox/token-secret | tr -d "'\r")"
export PROXMOX_VE_INSECURE=true

# ── PHASE 1: Verify VM exists ──────────────────────────────────────────────
CURRENT_PHASE="phase1-verify"
if ! ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm status $VM_ID" >/dev/null 2>&1; then
  warn "Phase 1/4 — VM $VM_ID not found; nothing to destroy (or already destroyed)."
  exit 0
fi
info "Phase 1/4 — VM $VM_ID exists, proceeding"

# ── PHASE 2: Unlink data disk (PRESERVED) ─────────────────────────────────
CURRENT_PHASE="phase2-unlink-data-disk"
info "Phase 2/4 — unlink data disk (preserved in $STORAGE_POOL)"
ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm unlink $VM_ID --idlist virtio1" 2>&1 | tee -a "$LOG_FILE"
info "Phase 2/4 — verify detach state (data disk must NOT be destroyable)"
ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm config $VM_ID | grep -E 'virtio1|unused' || echo 'no data disk in config — preserved'" 2>&1 | tee -a "$LOG_FILE"

# ── PHASE 3: Terraform destroy (VM + root disk only) ──────────────────────
CURRENT_PHASE="phase3-terraform-destroy"
info "Phase 3/4 — terraform destroy (VM + root disk; data disk preserved)"
cd "$SCRIPT_DIR/terraform"
terraform destroy -auto-approve -input=false 2>&1 | tee -a "$LOG_FILE"

# ── PHASE 4: Final verify ──────────────────────────────────────────────────
CURRENT_PHASE="phase4-verify"
info "Phase 4/4 — verify data disk still present"
ssh $SSH_OPTS "root@$PROXMOX_HOST" "pvesm list $STORAGE_POOL --vmid $VM_ID 2>/dev/null | grep -q '$VOLID' && echo 'DATA DISK PRESERVED: $VOLID' || echo 'WARN: data disk NOT found!'" 2>&1 | tee -a "$LOG_FILE"

info "destroy.sh COMPLETE — VM destroyed, data disk $VOLID preserved in $STORAGE_POOL"
info "Re-create with: ./create.sh"
exit 0
