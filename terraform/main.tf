resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = "local" # dir storage holds the import file; imported into local-lvm
  node_name    = var.node_name
  url          = var.cloud_image_url
  file_name    = var.cloud_image_filename
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ${var.hostname}
    timezone: Europe/Rome
    users:
      - default
      - name: bootstrap
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(var.ssh_public_key)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
    EOF

    file_name = "hermes-user-data-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "hermes" {
  name      = var.hostname
  node_name = var.node_name
  vm_id     = var.vm_id

  description = "Hermes Agent — dedicated KVM VM (managed by hermes-agent repo)"

  machine = "q35"
  bios    = "ovmf"

  started         = true
  stop_on_destroy = true

  # CRITICAL: default is true, which would delete the persistent data disk
  # (vm-<VMID>-disk-1, attached outside Terraform via qm set) on destroy.
  delete_unreferenced_disks_on_destroy = false

  agent {
    enabled = true
  }

  efi_disk {
    datastore_id = var.storage_pool
    type         = "4m"
  }

  cpu {
    cores   = var.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.storage_pool
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.root_disk_gb
    import_from  = proxmox_download_file.ubuntu_cloud_image.id
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
  }

  network_device {
    bridge = "vmbr0"
  }
}
