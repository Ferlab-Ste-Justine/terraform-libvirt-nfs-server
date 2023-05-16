variable "name" {
  description = "Name of the vm"
  type = string
}

variable "vcpus" {
  description = "Number of vcpus to assign to the vm"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Amount of memory in MiB"
  type        = number
  default     = 8192
}

variable "volume_id" {
  description = "Id of the disk volume to attach to the vm"
  type        = string
}

variable "data_volume_id" {
  description = "Id for an optional separate disk volume to attach to the vm on nfs' data path"
  type        = string
  default     = ""
}

variable "libvirt_network" {
  description = "Parameters of the libvirt network connection if a libvirt network is used. Has the following parameters: network_id, ip, mac"
  type = object({
    network_name = string
    network_id = string
    ip = string
    mac = string
  })
  default = {
    network_name = ""
    network_id = ""
    ip = ""
    mac = ""
  }
}

variable "macvtap_interfaces" {
  description = "List of macvtap interfaces. Mutually exclusive with the libvirt_network Field. Each entry has the following keys: interface, prefix_length, ip, mac, gateway and dns_servers"
  type        = list(object({
    interface = string
    prefix_length = string
    ip = string
    mac = string
    gateway = string
    dns_servers = list(string)
  }))
  default = []
}

variable "cloud_init_volume_pool" {
  description = "Name of the volume pool that will contain the cloud init volume"
  type        = string
}

variable "cloud_init_volume_name" {
  description = "Name of the cloud init volume"
  type        = string
  default = ""
}

variable "ssh_admin_user" { 
  description = "Pre-existing ssh admin user of the image"
  type        = string
  default     = "ubuntu"
}

variable "admin_user_password" { 
  description = "Optional password for admin user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_admin_public_key" {
  description = "Public ssh part of the ssh key the admin will be able to login as"
  type        = string
}

/*
See:
https://ubuntu.com/server/docs/service-nfs
https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/storage_administration_guide/nfs-serverconfig
*/
variable "nfs_configs" {
  description = "List of nfs configurations containing a subset of possible nfs configurations. It is a list of objects, each entry containing the following fields: path, domain, rw (true or false), sync (true or false), subtree_check (true or false), no_root_squash (true or false)"
  type        = list(object({
    path = string
    rw = bool
    sync = bool
    subtree_check = bool
    no_root_squash = bool
  }))
  default = []
}

variable "nfs_tunnel" {
  description = "Configuration for the nfs tunnel over tls"
  sensitive   = true
  type        = object({
    listening_port     = string
    server_key         = string
    server_certificate = string
    ca_certificate     = string
    max_connections    = number
    idle_timeout       = string
  })
}

variable "s3_backups" {
  description = "Configuration to continuously backup the nfs paths in s3"
  sensitive   = true
  type        = object({
    enabled                = bool
    restore                = bool
    symlinks               = string
    url                    = string
    region                 = string
    access_key             = string
    secret_key             = string
    server_side_encryption = string
    calendar               = string
    bucket                 = string
    ca_cert                = string
  })
  default = {
    enabled                = false
    restore                = false
    symlinks               = "copy"
    url                    = ""
    region                 = ""
    access_key             = ""
    secret_key             = ""
    server_side_encryption = ""
    calendar               = ""
    bucket                 = ""
    ca_cert                = ""
  }
}

variable "fluentd" {
  description = "Fluentd configurations"
  sensitive   = true
  type = object({
    enabled = bool
    nfs_tunnel_server_tag = string
    s3_backup_tag = string
    s3_restore_tag = string
    node_exporter_tag = string
    forward = object({
      domain = string
      port = number
      hostname = string
      shared_key = string
      ca_cert = string
    }),
    buffer = object({
      customized = bool
      custom_value = string
    })
  })
  default = {
    enabled = false
    nfs_tunnel_server_tag = ""
    s3_backup_tag = ""
    s3_restore_tag = ""
    node_exporter_tag = ""
    forward = {
      domain = ""
      port = 0
      hostname = ""
      shared_key = ""
      ca_cert = ""
    }
    buffer = {
      customized = false
      custom_value = ""
    }
  }
}

variable "chrony" {
  description = "Chrony configuration for ntp. If enabled, chrony is installed and configured, else the default image ntp settings are kept"
  type        = object({
    enabled = bool
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server
    servers = list(object({
      url = string,
      options = list(string)
    }))
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool
    pools = list(object({
      url = string,
      options = list(string)
    }))
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep
    makestep = object({
      threshold = number
      limit = number
    })
  })
  default = {
    enabled = false
    servers = []
    pools = []
    makestep = {
      threshold = 0
      limit = 0
    }
  }
}

variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
  type = bool
  default = true
}