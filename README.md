# Hermes Agent — Proxmox VM Deployment

Deployment of the Hermes Agent on a dedicated KVM VM (VM 501, Ubuntu 26.04 LTS) on the Proxmox node `tazlab`. Repo separato da `ephemeral-castle` — infra self-contained.

## Architecture

```
Proxmox "tazlab" (192.168.1.200)
└── VM 501 "hermes" (KVM, Ubuntu 26.04 LTS resolute)
    ├── 4 vCPU, 8 GB RAM
    ├── virtio0: root disk 30 GB (local-lvm) — DESTROYED with VM
    ├── virtio1: data disk 20 GB (local-lvm:vm-501-disk-2) — SURVIVES destroy
    │   └── /home/hermes (whole home = state + code, option A)
    ├── IP: 192.168.1.205/24, gw 192.168.1.1
    ├── Hermes v0.20+ (bare-metal via install.sh)
    │   ├── hermes-gateway.service
    │   └── hermes-dashboard.service (port 9119)
    └── Users: bootstrap (admin, sudo NOPASSWD), hermes (UID 10000, no sudo)
```

## Prerequisites

- `gopass` unlocked with these secrets (paths verified 2026-08-12):
  - `bootstrap/proxmox/token-id` + `bootstrap/proxmox/token-secret` — Proxmox API
  - `cluster/github/token` — repo push (TD-055 credential helper)
  - `infra/ssh-host-keys/hermes-agent/ed25519` — SSH host key (injected post-boot)
  - `infra/hermes-vm/bootstrap-password` + `infra/hermes-vm/hermes-password` — SSH passwords
- SSH key `~/.ssh/id_ed25519` (cloud-init + Ansible)
- Tools: terraform >= 1.5, ansible-core + `ansible.posix` + `community.general` collections

## Usage

```bash
./create.sh    # 8 phases: cleanup gate → pre-flight → terraform → attach → wait → ansible×4
./destroy.sh   # unlink data disk (preserved) → terraform destroy
```

- **First run**: creates VM, installs Hermes, dashboard on `http://192.168.1.205:9119`. Configure the LLM provider from the dashboard (first-access onboarding).
- **Subsequent runs after destroy**: data disk already populated → install skipped → services start with previous config. Zero re-onboarding (option A).
- Idempotent: re-running `create.sh` on a live VM is a no-op (terraform plan empty, Ansible unchanged).

## Persistent data disk (pet pattern)

- Created once: `pvesm alloc local-lvm 501 vm-501-disk-2 20G`
- Attached via `qm set 501 --virtio1 local-lvm:vm-501-disk-2` (outside Terraform state)
- `destroy.sh` unlinks it first → survives `terraform destroy`
- `delete_unreferenced_disks_on_destroy = false` in main.tf — required, otherwise Terraform deletes untracked disks
- NOTE: data disk is `vm-501-disk-2` (not `-1`): the provider assigns `disk-0` to the EFI disk and `disk-1` to root

## Logs

- `logs/create_<timestamp>.log`, `logs/destroy_<timestamp>.log`
- Rotation: keep last 20
- Error trap prints phase + line number + rerun hint

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `gopass` decryption fails | Cold GPG cache | Run `gopass show cluster/github/token` once interactively |
| apply slow ("Still creating") | `agent.enabled` waits for guest agent | Removed by design — agent installed by Ansible baseline |
| host key mismatch on SSH | Old key in known_hosts | `ssh-keygen -R 192.168.1.205` |
| Ansible `become` temp file error | Ansible 2.21 bug with non-root become | Fixed: `sudo -u hermes` pattern in roles |
| `libasound2` not found | Ubuntu 26.04 t64 rename | Use `libasound2t64` in baseline |

## Post-onboarding validation

After configuring the LLM provider in the dashboard, verify with:
```bash
ssh bootstrap@192.168.1.205
sudo -u hermes /home/hermes/.local/bin/hermes chat "ping" 
```
