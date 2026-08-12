output "vm_id" {
  value = proxmox_virtual_environment_vm.hermes.vm_id
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.hermes.name
}

output "vm_ip_address" {
  value = var.ip_address
}

# NOTE: inventory.ini and configs/runtime.env are STATIC files in the repo
# (not local_file resources). local_file resources got destroyed by
# `terraform destroy`, breaking create.sh/destroy.sh sourcing them.
