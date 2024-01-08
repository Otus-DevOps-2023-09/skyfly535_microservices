// packer {
//   required_plugins {
//     ansible = {
//       version = ">= 1.1.1"
//       source  = "github.com/hashicorp/ansible"
//     }
//   }
// }
variable "disk_size_gb" {
  type    = string
  default = ""
}
variable "folder_id" {
  type    = string
  default = ""
}

variable "service_account_key_file" {
  type    = string
  default = ""
}

variable "image_family" {
  type    = string
  default = ""
}

variable "source_image_family" {
  type    = string
  default = ""
}

variable "username" {
  type    = string
  default = ""
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "yandex" "autogenerated_1" {
  disk_size_gb             = "${var.disk_size_gb}"
  folder_id                = "${var.folder_id}"
  image_family             = "reddit-docker"
  image_name               = "reddit-docker-${local.timestamp}"
  platform_id              = "standard-v3"
  service_account_key_file = "${var.service_account_key_file}"
  source_image_family      = "${var.source_image_family}"
  ssh_username             = "${var.username}"
  use_ipv4_nat             = "true"
}

build {
  sources = ["source.yandex.autogenerated_1"]

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    pause_before     = "30s"
    inline = [
        # Set noninteractive mode
        "echo debconf debconf/frontend select Noninteractive | sudo debconf-set-selections",
        # Official guide: https://docs.docker.com/engine/install/ubuntu/
        "sudo apt-get -y update",
        "sudo apt-get -y upgrade",
        "sudo apt-get -y install apt-transport-https ca-certificates curl gnupg lsb-release",
        # Setup repo
        "sudo mkdir -p /etc/apt/keyrings",
        "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
        "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
        # Update repo
        "sudo apt-get -y update",
        # Install latest docker
        "sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin mc htop tmux",
        # Cleanup
        "sudo apt-get -y autoremove",
        "sudo apt-get -y clean"
    ]
  }

}
