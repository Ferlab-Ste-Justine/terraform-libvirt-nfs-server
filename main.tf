locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_interfaces = length(var.macvtap_interfaces) == 0 ? [{
    network_name = var.libvirt_network.network_name != "" ? var.libvirt_network.network_name : null
    network_id = var.libvirt_network.network_id != "" ? var.libvirt_network.network_id : null
    macvtap = null
    addresses = [var.libvirt_network.ip]
    mac = var.libvirt_network.mac != "" ? var.libvirt_network.mac : null
    hostname = var.name
  }] : [for macvtap_interface in var.macvtap_interfaces: {
    network_name = null
    network_id = null 
    macvtap = macvtap_interface.interface
    addresses = null
    mac = macvtap_interface.mac
    hostname = null
  }]
}

module "network_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//network?ref=v0.3.0"
  network_interfaces = var.macvtap_interfaces
}

module "nfs_server_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//nfs-server?ref=v0.3.0"
  install_dependencies = var.install_dependencies
  proxy = {
    server_name     = var.name
    max_connections = var.nfs_tunnel.max_connections
    idle_timeout    = var.nfs_tunnel.idle_timeout
    listening_port  = var.nfs_tunnel.listening_port
  }
  nfs_configs = var.nfs_configs
  tls = {
    server_cert = var.nfs_tunnel.server_certificate
    server_key  = var.nfs_tunnel.server_key
    ca_cert     = var.nfs_tunnel.ca_certificate
  }
}

module "s3_backups" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//s3-syncs?ref=v0.3.0"
  object_store = {
    url                    = var.s3_backups.url
    region                 = var.s3_backups.region
    access_key             = var.s3_backups.access_key
    secret_key             = var.s3_backups.secret_key
    server_side_encryption = var.s3_backups.server_side_encryption
    ca_cert                = var.s3_backups.ca_cert
  }
  outgoing_sync = {
    calendar   = var.s3_backups.calendar
    bucket     = var.s3_backups.bucket
    paths      = [for nfs_config in var.nfs_configs : nfs_config.path]
    symlinks   = var.s3_backups.symlinks
  }
  incoming_sync = {
    sync_once  = true
    calendar   = var.s3_backups.calendar
    bucket     = var.s3_backups.bucket
    paths      = var.s3_backups.restore ? [for nfs_config in var.nfs_configs : nfs_config.path] : []
    symlinks   = var.s3_backups.symlinks
  }
  install_dependencies = var.install_dependencies
}

module "prometheus_node_exporter_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//prometheus-node-exporter?ref=v0.3.0"
  install_dependencies = var.install_dependencies
}

module "chrony_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//chrony?ref=v0.3.0"
  install_dependencies = var.install_dependencies
  chrony = {
    servers  = var.chrony.servers
    pools    = var.chrony.pools
    makestep = var.chrony.makestep
  }
}

module "fluentd_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//fluentd?ref=v0.3.0"
  install_dependencies = var.install_dependencies
  fluentd = {
    docker_services = []
    systemd_services = concat(var.s3_backups.enabled ? [{
      tag     = var.fluentd.s3_backup_tag
      service = "s3-outgoing-sync"
    }, {
      tag     = var.fluentd.s3_restore_tag
      service = "s3-incoming-sync"
    }] : [],
    [
      {
        tag     = var.fluentd.nfs_tunnel_server_tag
        service = "nfs-tunnel-server"
      },
      {
        tag     = var.fluentd.node_exporter_tag
        service = "node-exporter"
      }
    ])
    forward = var.fluentd.forward,
    buffer = var.fluentd.buffer
  }
}

locals {
  cloudinit_templates = concat([
      {
        filename     = "base.cfg"
        content_type = "text/cloud-config"
        content = templatefile(
          "${path.module}/files/user_data.yaml.tpl", 
          {
            hostname = var.name
            ssh_admin_public_key = var.ssh_admin_public_key
            ssh_admin_user = var.ssh_admin_user
            admin_user_password = var.admin_user_password
          }
        )
      },
      {
        filename     = "node_exporter.cfg"
        content_type = "text/cloud-config"
        content      = module.prometheus_node_exporter_configs.configuration
      },
      {
        filename     = "nfs_server.cfg"
        content_type = "text/cloud-config"
        content      = module.nfs_server_configs.configuration
      }
    ],
    var.s3_backups.enabled ? [{
      filename     = "s3_backups.cfg"
      content_type = "text/cloud-config"
      content      = module.s3_backups.configuration
    }] : [],
    var.chrony.enabled ? [{
      filename     = "chrony.cfg"
      content_type = "text/cloud-config"
      content      = module.chrony_configs.configuration
    }] : [],
    var.fluentd.enabled ? [{
      filename     = "fluentd.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentd_configs.configuration
    }] : [],
  )
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  dynamic "part" {
    for_each = local.cloudinit_templates
    content {
      filename     = part.value["filename"]
      content_type = part.value["content_type"]
      content      = part.value["content"]
    }
  }
}

resource "libvirt_cloudinit_disk" "nfs_server" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = length(var.macvtap_interfaces) > 0 ? module.network_configs.configuration : null
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "nfs_server" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  disk {
    volume_id = var.volume_id
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
      network_name = network_interface.value["network_name"]
      macvtap = network_interface.value["macvtap"]
      addresses = network_interface.value["addresses"]
      mac = network_interface.value["mac"]
      hostname = network_interface.value["hostname"]
    }
  }

  autostart = true

  cloudinit = libvirt_cloudinit_disk.nfs_server.id

  //https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/ubuntu/ubuntu-example.tf#L61
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}