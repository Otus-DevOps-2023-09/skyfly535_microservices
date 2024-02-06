resource "yandex_compute_instance" "node" {
  name = "${var.server_base_name}-${count.index}"
  zone = var.zone
  count = var.nodes_count

  resources {
    cores  = var.cpu_count
    memory = var.ram_size
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = var.disk_size
    }
  }

  network_interface {
    subnet_id = var.subnet_id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_key_path)}"
  }
}
