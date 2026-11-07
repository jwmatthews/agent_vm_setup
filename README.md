# Overview
This is a walk through of how I setup a Linux VM for my coding agents with Rex so that I may interact with the coding agents from my iPhone and/or speak with voice to GrokBot and have it direct the coding agents on the VM even while away from my home network.  

- Host: Fedora 44
- VM: Fedora 45

Note the host has 2 NICs, I'm using 1 of them as a bridged device and giving the VM a set IP and hostname from my Unifi setup.

## Links
- https://www.superlogical.com/rex/docs/installation
- https://www.superlogical.com/rex/docs/linux/server-modes

## LV Setup for virt images

1. Already had a VG named `fedora` from my previous setup
```
sudo vgs
VG     #PV #LV #SN Attr    VSize  VFree
fedora   1   1   0 wz--n-- <1.82t <1.72t
```

2. Create the LV and its filesystem
```
sudo lvcreate -L 500G -n libvirt fedora
sudo mkfs.xfs /dev/fedora/libvirt
```
3. Add it to fstab by UUID
```
UUID=$(sudo blkid -s UUID -o value /dev/fedora/libvirt)
echo "UUID=$UUID  /var/lib/libvirt/images  xfs  defaults  0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

4. Mount it, then fix permissions and the SELinux label
```
sudo mount /var/lib/libvirt/images
sudo chmod 711 /var/lib/libvirt/images
sudo restorecon -Rv /var/lib/libvirt/images
```

## Prepare the base image
```
mkdir -p /var/lib/libvirt/images/base
cd /var/lib/libvirt/images/base
curl -LO https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-45-1.4.x86_64.qcow2
cd ..
qemu-img convert -O qcow2 base/Fedora-Cloud-Base-Generic-45-*.qcow2 agent-01.qcow2
qemu-img resize agent-01.qcow2 150G

```

## Setup 2nd NIC as a bridge device
```
sudo nmcli con add type bridge ifname br0 con-name br0 bridge.stp no \
     ipv4.method disabled ipv6.method disabled
sudo nmcli con add type ethernet ifname enp86s0 port-type bridge controller br0 con-name br0-port
sudo nmcli con modify "Wired connection 2" connection.autoconnect no
sudo nmcli con down "Wired connection 2"
sudo nmcli con up br0
```

## Create the VM with a cloud-init

```
cat agent-01-user-data.yaml
#cloud-config
hostname: agent-01
fqdn: agent-01.replaceme
prefer_fqdn_over_hostname: false
users:
  - name: jmatthews
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 replaceme
ssh_pwauth: false
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
```

```
virt-install \
  --name agent-01 \
  --memory 16384 --vcpus 10 --cpu host-passthrough \
  --osinfo fedora-unknown \
  --disk path=/var/lib/libvirt/images/agent-01.qcow2,format=qcow2,bus=virtio,discard=unmap \
  --import \
  --network bridge=br0,model=virtio,mac=52:54:00:a6:01:01 \
  --cloud-init user-data=./agent-01-user-data.yaml \
  --graphics none --console pty,target_type=serial \
  --autostart \
  --noautoconsole

virsh autostart agent-01     # start with the host
```

## Install Rex
```
printf '[rex]\nname=Rex (snapshot)\nbaseurl=https://pkgs.superlogical.com/rex/rpm/snapshot/$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://pkgs.superlogical.com/rex/keys/rex.asc\n' | sudo install -m 0644 /dev/stdin /etc/yum.repos.d/rex.repo
sudo dnf install rex
```

## Setup tailscale with Rex
I already have a tailscale account set up, so I can use that to authenticate with Rex.

Below is setting up tailscale for this VM itself, this is NOT needed, just something I did so I could access the VM if I needed to without Rex.
```
sudo dnf install tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
``` 

Below is creating a second tailscale connection for the Rex service itself
```
rex server tailscale on
rex server status
# I followed the URL to authenticate this to my tailscale
```

## Setting up Rex to start on boot as my user
I am running as the user `jmatthews` and I'm using systemd to start Rex on boot as my user.

```
cat .config/systemd/user/rex.service
[Unit]
Description=Rex personal server

[Service]
ExecStart=/usr/bin/rex server run --tailscale --log-format text
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

```
sudo loginctl enable-linger jmatthews
systemctl --user daemon-reload
systemctl --user enable --now rex.service
systemctl --user status rex.service
journalctl --user -u rex -f
```
