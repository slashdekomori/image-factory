packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

source "qemu" "system" {
  # Base image: boot the cloud image directly, no ISO install
  iso_url          = "./image/redos-8-cloud.qcow2"
  iso_checksum     = "none"
  disk_image       = true
  use_backing_file = false # true = small overlay depending on the base file
  disk_size        = "20G" # grown at first boot by cloud-init growpart
  format           = "qcow2"

  # VM hardware (genericcloud kernel needs virtio)
  accelerator    = "kvm"
  cpus           = 2
  memory         = 2048
  disk_interface = "virtio"
  net_device     = "virtio-net"
  headless       = true # set false to watch the console

  # cloud-init seed, attached as a CD labelled "cidata"
  # (needs xorriso, genisoimage or mkisofs on the host)
  cd_label = "cidata"
  cd_files = [
    "cloud-init/user-data",
    "cloud-init/meta-data",
  ]

  # Compression
  disk_compression   = true    # qemu-img convert -c on the output
  disk_discard       = "unmap" # lets fstrim actually free blocks
  disk_detect_zeroes = "unmap" # zeroed blocks are dropped too
  skip_compaction    = false   # (default) keep the compaction pass

  # No boot_command needed: the image boots itself
  communicator         = "ssh"
  ssh_username         = "packer"
  ssh_private_key_file = "packer_key"
  ssh_password         = "packer"
  ssh_timeout          = "10m"
  shutdown_command     = ""
  shutdown_timeout     = "5m"

  output_directory = "output"
  vm_name          = "redos-8-friendly.qcow2"
}

build {
  sources = ["source.qemu.system"]

  # Wait for first-boot cloud-init to finish before touching the system
  provisioner "shell" {
    inline = ["sudo cloud-init status --wait"]
  }

  # Packages
  provisioner "shell" {
    inline = [
      "sudo dnf -y makecache",
      "sudo dnf -y upgrade",
      "sudo dnf -y install tmux vim-enhanced btop curl fastfetch qemu-guest-agent",
      "sudo systemctl enable qemu-guest-agent",
    ]
  }

  # Upload the /etc/issue
  provisioner "file" {
    source      = "files/issue"
    destination = "/tmp/issue"
  }
  provisioner "shell" {
    inline = [
      "sudo install -o root -g root -m 0644 /tmp/issue /etc/issue",
      "sudo install -o root -g root -m 0644 /tmp/issue /etc/issue.net",
      "rm -f /tmp/issue",
    ]
  }

  # Generic cleanup
  provisioner "shell" {
    inline = [
      "sudo dnf -y autoremove",
      "sudo dnf clean all",
      "sudo rm -rf /var/cache/dnf",
      "sudo cloud-init clean --logs --seed --configs network",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo rm -f /etc/ssh/ssh_host_*",
    ]
  }

  # Upload the user-removal script
  provisioner "file" {
    source      = "scripts/remove-build-users.sh"
    destination = "/tmp/remove-build-users.sh"
  }
  # Install it and start it detached, so it outlives our SSH session
  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "sudo install -o root -g root -m 0700 /tmp/remove-build-users.sh /root/remove-build-users.sh",
      "rm -f /tmp/remove-build-users.sh",
      "sudo systemd-run --no-block --unit=remove-build-users /root/remove-build-users.sh",
    ]
  }
}
