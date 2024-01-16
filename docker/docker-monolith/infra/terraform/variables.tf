variable "service_account_key_file" {
  description = "Path to service account key file"
}

variable "cloud_id" {
  description = "Cloud"
}

variable "folder_id" {
  description = "Folder"
}

variable "zone" {
  description = "Zone"
  default     = "ru-central1-a"
}

variable "image_id" {
  description = "Image id for VM"
}

variable "subnet_id" {
  description = "ID for subnet"
}

variable "public_key_path" {
  description = "Path to the public key used for ssh access"
}

variable "servers_count" {
  description = "Number of servers to create"
  default     = 1
}
