#!/usr/env/bin bash

set -euo pipefail

# I think have Unifi network configure a fixed IP and DNS for the below MAC
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
