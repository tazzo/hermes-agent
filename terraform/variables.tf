variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
  default     = 501
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "tazlab"
}

variable "ip_address" {
  description = "Static IP for the VM"
  type        = string
  default     = "192.168.1.205"
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.1.1"
}

variable "hostname" {
  description = "VM hostname"
  type        = string
  default     = "hermes"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
  default     = 8192
}

variable "root_disk_gb" {
  description = "Root disk size in GB (ephemeral, destroyed with VM)"
  type        = number
  default     = 30
}

variable "data_disk_gb" {
  description = "Persistent data disk size in GB (vm-<VMID>-disk-1, survives destroy)"
  type        = number
  default     = 20
}

variable "storage_pool" {
  description = "Proxmox storage pool"
  type        = string
  default     = "local-lvm"
}

variable "ssh_public_key" {
  description = "SSH public key for the bootstrap user (cloud-init)"
  type        = string
}

variable "cloud_image_url" {
  description = "Ubuntu cloud image URL"
  type        = string
  default     = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}

variable "cloud_image_filename" {
  description = "Cloud image file name (must end in .qcow2 for import)"
  type        = string
  default     = "resolute-server-cloudimg-amd64.qcow2"
}
