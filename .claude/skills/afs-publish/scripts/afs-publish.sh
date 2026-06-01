#!/bin/sh
# Publish web content to a Stanford AFS WWW directory over the persistent SSH
# master (open it first with afs-open-master.sh). A single FILE is published
# ATOMICALLY (write a sibling .new, then mv over the target, refusing a symlinked
# target); a DIRECTORY is synced with rsync (NOT atomic). Either way, the Stanford
# web server is granted read on the target directory. See README Parts 2c, 3a, 5b, 5e.
#
# Usage:
#   afs-publish.sh <local_path> <remote_afs_dir> [remote_name]
#     local_path      file or directory on this machine
#     remote_afs_dir  absolute AFS dir, e.g. /afs/ir/users/j/d/jdoe/WWW
#                     (or a subdir, e.g. .../WWW/private)
#     remote_name     target filename for a single file (default: basename of local_path)
#
# Env:
#   AFS_SSH_HOST  SSH host alias (default: farmshare)
#   AFS_PUBLIC    "1" also grants system:anyuser read (PUBLIC page). Omit/0 for a
#                 WebAuth-protected dir, where system:anyuser must NOT have read.
set -eu

host="${AFS_SSH_HOST:-farmshare}"
local_path="${1:?usage: afs-publish.sh <local_path> <remote_afs_dir> [remote_name]}"
remote_dir="${2:?missing <remote_afs_dir> (e.g. /afs/ir/users/j/d/jdoe/WWW)}"
remote_name="${3:-$(basename "$local_path")}"
public="${AFS_PUBLIC:-0}"

# Remote logic is executed by /bin/sh on the FAR side because FarmShare's login
# shell is tcsh — Bourne syntax sent via `ssh host '<cmd>'` would fail (README 5b).
run_remote() { ssh "$host" /bin/sh; }

# Fail fast if the master isn't live, so automation never blocks on a Duo prompt.
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" true 2>/dev/null; then
  echo "No live SSH master to '$host'. Run afs-open-master.sh first." >&2
  exit 1
fi

if [ -d "$local_path" ]; then
  echo "Syncing directory '$local_path/' -> $host:$remote_dir/  (rsync; NOT atomic)…"
  # AFS uses ACLs, not UNIX perms — don't try to preserve perms/dir times.
  rsync -avz --no-perms --omit-dir-times "$local_path"/ "$host:$remote_dir"/
elif [ -f "$local_path" ]; then
  echo "Atomically publishing file '$local_path' -> $host:$remote_dir/$remote_name…"
  scp -q "$local_path" "$host:$remote_dir/$remote_name.new"
  run_remote <<EOF
set -eu
cd "$remote_dir"
# Refuse to follow a pre-existing symlink at the target (prevents a hijacked write).
if [ -L "$remote_name" ]; then echo "refusing: $remote_dir/$remote_name is a symlink" >&2; exit 1; fi
mv -f "$remote_name.new" "$remote_name"
EOF
else
  echo "local_path not found: $local_path" >&2
  exit 1
fi

# Ensure the web server can read the directory (rl); optionally make it public.
echo "Ensuring AFS ACLs on $remote_dir (public=$public)…"
if [ "$public" = "1" ]; then
  run_remote <<EOF
set -eu
fs sa "$remote_dir" system:www-servers read
fs sa "$remote_dir" system:anyuser read
fs la "$remote_dir"
EOF
else
  run_remote <<EOF
set -eu
fs sa "$remote_dir" system:www-servers read
fs la "$remote_dir"
EOF
fi
echo "Done."
