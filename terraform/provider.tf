provider "proxmox" {
  # Auth via env vars (exported by create.sh from gopass, never stored):
  #   PROXMOX_VE_API_TOKEN = "<token-id>=<secret>"
  #   PROXMOX_VE_ENDPOINT  = "https://192.168.1.200:8006/"
  #   PROXMOX_VE_INSECURE  = "true"   # self-signed cert
  endpoint = "https://192.168.1.200:8006/"
  insecure = true
}
