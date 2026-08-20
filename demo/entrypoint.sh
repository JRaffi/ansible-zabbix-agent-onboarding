#!/bin/sh
# Install the demo SSH key, then hand PID 1 over to systemd.
set -e

if [ -f /keys/id_ed25519.pub ]; then
  install -d -m 0700 -o ansible -g ansible /home/ansible/.ssh
  cp /keys/id_ed25519.pub /home/ansible/.ssh/authorized_keys
  chown ansible:ansible /home/ansible/.ssh/authorized_keys
  chmod 0600 /home/ansible/.ssh/authorized_keys
else
  echo "WARNING: /keys/id_ed25519.pub missing - SSH login will fail" >&2
fi

exec /sbin/init
