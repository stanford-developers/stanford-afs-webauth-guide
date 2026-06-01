#!/bin/sh
# Open (or reuse) a persistent, Duo-free SSH master to a Stanford FarmShare login
# node, so later scp/ssh/rsync to AFS need no Duo. See README Part 5a.
#
# Usage: afs-open-master.sh [ssh_host_alias]
#   ssh_host_alias  SSH config Host alias for FarmShare
#                   (default: $AFS_SSH_HOST, else "farmshare"). The alias MUST set
#                   ControlMaster auto, ControlPath, and ControlPersist yes — see
#                   examples/ssh-config-snippet.
#
# Run this in a REAL TERMINAL the first time: Duo is interactive and cannot be
# answered from a non-interactive/automated shell. Re-run after a reboot, sleep,
# or network drop to reopen the master; scheduled jobs then reuse it with no Duo.
set -eu

host="${1:-${AFS_SSH_HOST:-farmshare}}"
alive() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" true 2>/dev/null; }

if alive; then
  echo "AFS SSH master to '$host' is already live — no Duo needed."
  exit 0
fi

echo "No live master to '$host'. Opening one now — expect ONE Duo prompt."
echo "(If this hangs or errors, confirm '$host' is in ~/.ssh/config with"
echo " ControlMaster auto / ControlPath / ControlPersist yes.)"
ssh "$host" true

if alive; then
  echo "Master is up. scp/ssh/rsync to '$host' will reuse it (no Duo) until the"
  echo "Mac reboots/sleeps or the network drops."
else
  echo "Master still not reachable — check your SSH config and that Duo completed." >&2
  exit 1
fi
