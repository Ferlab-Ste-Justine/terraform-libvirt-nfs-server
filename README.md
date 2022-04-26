# About

This terraform module provisions a nfs server on libvirt/kvm.

It has been validated with a recent ubuntu image in a non-production context.

# Usage

## Variables

- **name**: Name to assign to the vm and accompanying resources
- **vcpus**: Number of virtual cores to assign to the vm
- **memory**: Amount of memory to assign to the vms in MiBs
- **volume_id**: Id of the volume to attach to the vm
- **libvirt_network**: If the vm is to connect to a libvirt network, parameters of the connection. This is an object containing the following properties: network_id, ip, mac
- **macvtap_interfaces**: List of macvtap interfaces to define for the vm. This is mutually exclusive with **libvirt_network**. Each entry in the list is an object with the following properties: interface, prefix_length, ip, mac, gateway, dns_servers
- **cloud_init_volume_pool**: Volume pool to use for the generate cloud init volume
- **cloud_init_volume_name**: Name of the generated cloud-init volume. If left empty, it will default to ```<name>-cloud-init.iso```.
- **ssh_admin_user**: Username of the default sudo user in the image. Defaults to **ubuntu**.
- **admin_user_password**: Optional password for the default sudo user of the image. Note that this will not enable ssh password connections, but it will allow you to log into the vm from the host using the **virsh console** command.
- **ssh_admin_public_key**: Public part of the ssh key the admin will be able to login as
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set the false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
- **nfs_configs**: List of nfs directory entries. Each entry is an object containing the following properties: path (string), domain (string), rw (bool), sync (bool), subtree_check (bool), no_root_squash (bool)

## Example

```
module "nfs_server" {
  source = "git::https://github.com/Ferlab-Ste-Justine/kvm-nfs-server.git"
  name = "nfs-server"
  vcpus = 1
  memory = 8192
  volume_id = libvirt_volume.nfs_server.id
  libvirt_network = {
      network_id = var.libvirt_network_id
      ip = var.ip
      mac = var.mac
  }
  cloud_init_volume_pool = "default"
  ssh_admin_public_key = tls_private_key.admin_ssh.public_key_openssh
  admin_user_password = "test"
  nfs_configs = [
      {
          path = "/opt/fs"
          domain = "*"
          rw = true
          sync = true
          subtree_check = false
          no_root_squash = true
      }
  ]
}
```