#!/usr/bin/env bash
# Cleanly shut down a libvirt VM, take a disk snapshot, and start it again.
#
# Usage: sudo ./vm-snapshot.sh <vm-name> <snapshot-name> ["description"]
# Example: sudo ./vm-snapshot.sh agent-01 clean-install "Fresh F45, cloud-init done"

set -euo pipefail

VM="${1:?usage: $0 <vm-name> <snapshot-name> [\"description\"]}"
SNAP="${2:?usage: $0 <vm-name> <snapshot-name> [\"description\"]}"
DESC="${3:-}"
TIMEOUT=300   # seconds to wait for a graceful shutdown

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo (needs qemu:///system)." >&2
  exit 1
fi

export LIBVIRT_DEFAULT_URI="qemu:///system"

state() { virsh domstate "$VM" 2>/dev/null | head -n1; }

if [[ "$(state)" != "shut off" ]]; then
  echo "Shutting down $VM..."
  virsh shutdown "$VM" >/dev/null

  waited=0
  until [[ "$(state)" == "shut off" ]]; do
    if (( waited >= TIMEOUT )); then
      echo "Timed out after ${TIMEOUT}s; $VM is still '$(state)'. Not snapshotting." >&2
      echo "Check the guest, or force it off with: virsh destroy $VM" >&2
      exit 1
    fi
    sleep 2
    (( waited += 2 ))
    printf '\r  waiting... %ds' "$waited"
  done
  echo
fi

echo "Creating snapshot '$SNAP'..."
if [[ -n "$DESC" ]]; then
  virsh snapshot-create-as "$VM" "$SNAP" "$DESC"
else
  virsh snapshot-create-as "$VM" "$SNAP"
fi

echo "Starting $VM..."
virsh start "$VM" >/dev/null

echo "Done. Snapshots for $VM:"
virsh snapshot-list "$VM"
