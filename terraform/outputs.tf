output "vm_id" {
  value = proxmox_virtual_environment_vm.hermes.vm_id
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.hermes.name
}

output "vm_ip_address" {
  value = var.ip_address
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    host       = var.ip_address
    ssh_key    = var.ssh_public_key
    ansible_user = "bootstrap"
  })
}

# Generate runtime.env for create.sh/destroy.sh
resource "local_file" "runtime_env" {
  filename = "${path.module}/../configs/runtime.env"
  content = templatefile("${path.module}/templates/runtime.env.tftpl", {
    vm_id          = var.vm_id
    ip_address     = var.ip_address
    hostname       = var.hostname
    cores          = var.cores
    memory_mb      = var.memory_mb
    root_disk_gb   = var.root_disk_gb
    data_disk_gb   = var.data_disk_gb
    storage_pool   = var.storage_pool
    volid          = "local-lvm:vm-${var.vm_id}-disk-1"
  })
}
