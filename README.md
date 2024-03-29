# About

This terraform module provisions a nfs server on libvirt/kvm.

This server provisions an envoy tunnel that accepts tls traffic with mutual certificate authentication from clients. The nfs traffic is expected to go through this tunnel and as such, the nfs port (2049) is not exposed to non-localhost traffic.

The client is expected to implement its end of the tunnel. A validated reference implementation for the client in cloud-init format can be found here: https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates/tree/main/nfs-client

Optional recurring synchronization against a backup s3-compatible object store is also supported.

# Usage

## Variables

- **name**: Name to assign to the vm and accompanying resources
- **vcpus**: Number of virtual cores to assign to the vm
- **memory**: Amount of memory to assign to the vms in MiBs
- **volume_id**: Id of the volume to attach to the vm
- **data_volume**: Optional variable to separate disk volume to attach to the vm on nfs' data path
  - **id**: Id for an optional separate disk volume.
  - **path**: Path for an optional separate disk volume.
- **libvirt_network**: Parameters to connect to libvirt networks. Each entry has the following keys:
  - **network_id**: Id (ie, uuid) of the libvirt network to connect to (in which case **network_name** should be an empty string).
  - **network_name**: Name of the libvirt network to connect to (in which case **network_id** should be an empty string).
  - **ip**: Ip of interface connecting to the libvirt network.
  - **mac**: Mac address of interface connecting to the libvirt network.
  - **prefix_length**:  Length of the network prefix for the network the interface will be connected to. For a **192.168.1.0/24** for example, this would be **24**.
  - **gateway**: Ip of the network's gateway. Usually the gateway the first assignable address of a libvirt's network.
  - **dns_servers**: Dns servers to use. Usually the dns server is first assignable address of a libvirt's network.
- **macvtap_interfaces**: List of macvtap interfaces to connect the vm to if you opt for macvtap interfaces. Each entry in the list is a map with the following keys:
  - **interface**: Host network interface that you plan to connect your macvtap interface with.
  - **prefix_length**: Length of the network prefix for the network the interface will be connected to. For a **192.168.1.0/24** for example, this would be 24.
  - **ip**: Ip associated with the macvtap interface. 
  - **mac**: Mac address associated with the macvtap interface
  - **gateway**: Ip of the network's gateway for the network the interface will be connected to.
  - **dns_servers**: Dns servers for the network the interface will be connected to. If there aren't dns servers setup for the network your vm will connect to, the ip of external dns servers accessible accessible from the network will work as well.
- **cloud_init_volume_pool**: Volume pool to use for the generate cloud init volume
- **cloud_init_volume_name**: Name of the generated cloud-init volume. If left empty, it will default to ```<name>-cloud-init.iso```.
- **ssh_admin_user**: Username of the default sudo user in the image. Defaults to **ubuntu**.
- **admin_user_password**: Optional password for the default sudo user of the image. Note that this will not enable ssh password connections, but it will allow you to log into the vm from the host using the **virsh console** command.
- **ssh_admin_public_key**: Public part of the ssh key the admin will be able to login as
- **nfs_tunnel**: Configuration for the nfs tunnel that will listen for tls client traffic. It has the following keys:
  - **listening_port**: Post the tunnel will listen on
  - **server_key**: Server private key for the tunnel listener
  - **server_certificate**: Server certificate for the tunnel listener
  - **ca_certificate**: Certificate of the CA that will be used to validate client certificates
  - **max_connections**: Max number of connections that will be accepted
  - **idle_timeout**: Amount of time a connection with no traffic will be allowed to live before it is forcefully terminated.
- **nfs_configs**: List of nfs directory entries. Each entry is an object containing the following properties: path (string), rw (bool), sync (bool), subtree_check (bool), no_root_squash (bool)
- **s3_backups**: Configuration to continuously synchronize the directories exposed by the nfs server on an s3-compatible object store bucket. It has the following keys:
  - **enabled**: Whether enable to s3 backups.
  - **restore**: If set to true, an incoming synchronization will be done once from the backups when the vm is created, and before backups are started, to populate the nfs directories with backed up data.
  - **symlinks**: Determines how symlinks will be handled. Can be **skip** (symlinks will be ignored), **copy** (symlinks will be preserved) or **follow** (the destination file of the symlinks will be copied)
  - **url**: Url of the s3-compatible object store
  - **region**: Region to use in the object store
  - **access_key**: User id for the object store
  - **secret_key**: User password for the object store
  - **server_side_encryption**: Encryption format (ex: **aws:kms**) of the s3 bucket if any. An empty string can be passed if the bucket is not encrypted. It will be passed to the **server_side_encryption** property in rclone's configuration.
  - **calendar**: Frequency of the backup synchronization, in systemd time format (see: https://www.freedesktop.org/software/systemd/man/systemd.time.html#)
  - **bucket**: Bucket to backup the filesystem info. 
  - **ca_cert**: Optional CA certificate to use to authentify the object store's server certificate. Can be left empty if the object store doesn't use https or has a server certificate that is signed by a CA already in the vm's system.
- **fluentbit**: Optional fluend configuration to securely route logs to a fluend/fluent-bit node using the forward plugin. Alternatively, configuration can be 100% dynamic by specifying the parameters of an etcd store to fetch the configuration from. It has the following keys:
  - **enabled**: If set the false (the default), fluent-bit will not be installed.
  - **nfs_tunnel_server_tag**: Tag to assign to logs coming from the nfs tunnel server
  - **s3_backup_tag**: Tag to assign to logs coming from the s3 backup service, if it is enabled
  - **s3_restore_tag**: Tag to assign to logs coming from the s3 restore service which runs once when the vm is created, if it is enabled
  - **node_exporter_tag** Tag to assign to logs coming from the prometheus node exporter
  - **forward**: Configuration for the forward plugin that will talk to the external fluend/fluent-bit node. It has the following keys:
    - **domain**: Ip or domain name of the remote fluend node.
    - **port**: Port the remote fluend node listens on
    - **hostname**: Unique hostname identifier for the vm
    - **shared_key**: Secret shared key with the remote fluentd node to authentify the client
    - **ca_cert**: CA certificate that signed the remote fluentd node's server certificate (used to authentify it)
  - **etcd**: Parameters to fetch fluent-bit configurations dynamically from an etcd cluster. It has the following keys:
    - **enabled**: If set to true, configurations will be set dynamically. The default configurations can still be referenced as needed by the dynamic configuration. They are at the following paths:
      - **Global Service Configs**: /etc/fluent-bit-customization/default-config/fluent-bit-service.conf
      - **Systemd Inputs**: /etc/fluent-bit-customization/default-config/fluent-bit-inputs.conf
      - **Forward Output**: /etc/fluent-bit-customization/default-config/fluent-bit-output.conf
    - **key_prefix**: Etcd key prefix to search for fluent-bit configuration
    - **endpoints**: Endpoints of the etcd cluster. Endpoints should have the format `<ip>:<port>`
    - **ca_certificate**: CA certificate against which the server certificates of the etcd cluster will be verified for authenticity
    - **client**: Client authentication. It takes the following keys:
      - **certificate**: Client tls certificate to authentify with. To be used for certificate authentication.
      - **key**: Client private tls key to authentify with. To be used for certificate authentication.
      - **username**: Client's username. To be used for username/password authentication.
      - **password**: Client's password. To be used for username/password authentication.
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set the false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
- **install_dependencies**: Whether cloud-init should install external dependencies (should be set to false if you already provide an image with the external dependencies built-in).

## Example

```
module "nfs_ca" {
  source = "./ca"
  common_name = "nfs"
}

resource "tls_private_key" "nfs_tunnel_server_key" {
  algorithm   = "RSA"
  rsa_bits    = 4096
}

resource "tls_cert_request" "nfs_tunnel_server_request" {
  private_key_pem = tls_private_key.nfs_tunnel_server_key.private_key_pem
  subject {
    common_name  = "nfs-server"
    organization = "Ferlab"
  }
  dns_names       = ["nfs.mydomain.com"]
}

resource "tls_locally_signed_cert" "nfs_tunnel_server_certificate" {
  cert_request_pem   = tls_cert_request.nfs_tunnel_server_request.cert_request_pem
  ca_private_key_pem = module.nfs_ca.key
  ca_cert_pem        = module.nfs_ca.certificate

  validity_period_hours = 100 * 365 * 24
  early_renewal_hours = 365 * 24

  allowed_uses = [
    "server_auth",
  ]

  is_ca_certificate = false
}

module "nfs_server" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-libvirt-nfs-server.git"
  name = "ferlab-nfs"
  vcpus = local.params.nfs.vcpus
  memory = local.params.nfs.memory
  volume_id = libvirt_volume.nfs.id
  libvirt_networks = [{
    network_name = "ferlab"
    network_id = ""
    ip = data.netaddr_address_ipv4.nfs.address
    mac = data.netaddr_address_mac.nfs.address
    gateway = local.params.network.gateway
    dns_servers = [local.params.network.dns]
    prefix_length = split("/", local.params.network.addresses).1
  }]
  cloud_init_volume_pool = "default"
  ssh_admin_public_key = tls_private_key.admin_ssh.public_key_openssh
  admin_user_password = local.params.virsh_console_password
  nfs_configs = [
    {
      path = "/opt/fs"
      rw = true
      sync = true
      subtree_check = false
      no_root_squash = true
    }
  ]
  nfs_tunnel = {
    listening_port     = 2050
    server_key         = tls_private_key.nfs_tunnel_server_key.private_key_pem
    server_certificate = tls_locally_signed_cert.nfs_tunnel_server_certificate.cert_pem
    ca_certificate     = module.nfs_ca.certificate
    max_connections    = 1000
    idle_timeout       = "600s"
  }
}

module "nfs_domain" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-etcd-zonefile.git"
  domain = "nfs.mydomain.com"
  key_prefix = "/ferlab/coredns/"
  dns_server_name = "ns.mydomain.com."
  a_records = [{
    prefix = ""
    ip = data.netaddr_address_ipv4.nfs.address
  }]
}
```