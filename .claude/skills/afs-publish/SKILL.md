---
name: Stanford AFS + WebAuth publishing
description: >-
  Connect to Stanford AFS over SSH/SFTP (FarmShare; no OpenAFS client), publish or
  update a website in an AFS WWW directory (served at web.stanford.edu/~SUNETID),
  protect pages with WebAuth via .htaccess, authorize access by a Stanford workgroup,
  and automate or schedule unattended AFS deploys (persistent Duo-free SSH master,
  Kerberos/AFS token refresh, atomic publish). Use for any Stanford AFS, WebAuth,
  web.stanford.edu personal site, FarmShare, or aklog/kinit token task.
---

# Stanford AFS + WebAuth publishing

Operational companion to this repo's `README.md` (Parts 1–6 + Troubleshooting). Use it to
**connect** to AFS, **publish/update** a `web.stanford.edu/~SUNETID` site, gate it behind
**WebAuth**, authorize by **workgroup**, and **automate** unattended deploys — with the
Stanford-specific gotchas already handled.

> **New sites:** AFS web hosting is being retired — prefer a current hosting option
> (README Part 6). This skill is for keeping **existing** AFS sites working and fresh —
> say so if the user is starting something new.

Throughout, replace `<sunetid>` with the user's SUNet ID and use their AFS path. Examples
use `jdoe`.

## Before any task — establish identity & connection

1. **SUNet ID.** Read it from `~/.ssh/config` (the FarmShare `Host` block's `User`), else
   from context, else **ask**. Never guess.
2. **AFS paths.** Home = `/afs/ir/users/<1st letter>/<2nd letter>/<sunetid>`; web root =
   that path + `/WWW`. Public URL = `https://web.stanford.edu/~<sunetid>/`.
   (e.g. `jdoe` → `/afs/ir/users/j/d/jdoe/WWW`.)
3. **SSH alias.** Confirm `~/.ssh/config` has a FarmShare `Host` with `ControlMaster auto`,
   `ControlPath`, and `ControlPersist` (see [`examples/ssh-config-snippet`](../../../examples/ssh-config-snippet)).
   If missing, offer to add it. Default alias used by the bundled scripts is `farmshare`
   (override with `AFS_SSH_HOST`).
4. **Connection check (no Duo if a master is live):**
   `ssh -o BatchMode=yes -o ConnectTimeout=10 farmshare 'tokens'` — a live master prints an
   AFS token for `ir.stanford.edu`. If it fails with a 2FA/permission error, the master is
   down → open one (see **Automate**, step A).

## Task router

### Connect / set up SSH (README Part 1)
- Ensure the `~/.ssh/config` alias from step 3 exists (`chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/config`).
- `ssh farmshare` (SUNet password, then Duo). **First connect**, verify the host key:
  - ED25519 `SHA256:bKb1Znir/1tOg+TMyALDYWeK0lclsulriDN8aOvWteU`
  - RSA `SHA256:o5E5OOkaxwF+CzKT5A2/DNSmDzljTYs/a1V7Fm6ssSw`
- Confirm token: remote `tokens`; if `/afs` gives *permission denied*, run remote `aklog`.
- FarmShare `HOME` is **not** AFS — AFS is the separate tree at `/afs`.

### Publish a PUBLIC page (README Part 2)
- Push content, then make the directory web-readable:
  - `AFS_PUBLIC=1 ${CLAUDE_SKILL_DIR}/scripts/afs-publish.sh ./index.html /afs/ir/users/j/d/jdoe/WWW`
  - or a whole site dir: `AFS_PUBLIC=1 ${CLAUDE_SKILL_DIR}/scripts/afs-publish.sh ./site/ /afs/ir/users/j/d/jdoe/WWW`
- Equivalent by hand: `rsync -avz ./site/ farmshare:.../WWW/` then remote
  `fs sa . system:www-servers read` and (public only) `fs sa . system:anyuser read`.

### Publish a WEBAUTH-PROTECTED page (README Part 3)
1. ACL: web server may read, anonymous may **not**:
   - remote: `cd <dir>; fs sa . system:www-servers read; fs sa . system:anyuser none; fs la`
   - or just omit `AFS_PUBLIC` when using `afs-publish.sh` (it grants only `system:www-servers read`).
2. Add `.htaccess` in that directory (copy from [`examples/`](../../../examples/)). Variants:
   - Any Stanford affiliate:
     ```apache
     AuthType WebAuth
     require privgroup stanford:stanford
     ```
   - Specific people: `require user jdoe gsmith lwilliams`
   - Group + yourself: `require privgroup stanford:student` then `require user jdoe`
3. **Critical:** the `.htaccess` must end with a real trailing newline or Apache may
   silently ignore it. After writing it, verify: remote `tail -c1 <dir>/.htaccess | od -An -c`
   should show `\n`. List it with `ls -a` (it's a dotfile).
4. Test in an incognito window (you should hit WebLogin); best, have an *unauthorized*
   person confirm they're denied.

### Authorize by Stanford workgroup (README Part 4)
- `.htaccess`: `require privgroup stem:name` (e.g. `~jdoe:website-editors`). Manage groups
  at workgroup.stanford.edu.
- If authorized members are denied, the group's **visibility** likely doesn't permit web
  authorization — fix in Workgroup Manager (README Part 4c / Troubleshooting).

### Automate / schedule unattended deploys (README Part 5)
- **A. Open the one-Duo persistent master** (do this in a real terminal; Duo is interactive):
  `${CLAUDE_SKILL_DIR}/scripts/afs-open-master.sh` — it reuses a live master or opens one
  with a single Duo. Re-run after reboot/sleep/network drop. (If you can't run it here,
  tell the user to run it themselves in their terminal.)
- **B. Deploy reuses the master, no Duo:** schedule `afs-publish.sh …` from cron/`launchd`.
  It fails fast (no hanging Duo prompt) if the master is down.
- **C. Tokens for long jobs (Duo-free):** `kinit` and `aklog` don't go through Duo.
  Mint renewable tickets and refresh: `kinit --forwardable --renewable --password-file=<file> <sunetid>@stanford.edu; aklog ir.stanford.edu`;
  refresh with `kinit -R` (over a delegated master, run `kinit -R` on the **remote** side).
- **D. Liveness gate** for any scheduled job:
  `ssh -o BatchMode=yes -o ConnectTimeout=10 farmshare true && <deploy> || <alert: re-auth needed>`.

### Troubleshoot
Use the table in `README.md` → **Troubleshooting**. Most common:
- `permission denied` under `/afs` → no/expired token → remote `aklog` (and `kinit -R`).
- Page loads for everyone despite `.htaccess` → missing trailing newline / wrong filename / wrong dir.
- `403` for everyone → web server can't read → `fs sa . system:www-servers read`.
- Repeated Duo per transfer → add `ControlMaster`/`ControlPersist`.
- `Illegal variable name` on a remote command → FarmShare shell is tcsh → wrap in `sh -c`.

## Bundled scripts
Both are POSIX `sh`, take the SSH alias from `$AFS_SSH_HOST` (default `farmshare`), and
assume the alias has `ControlMaster`/`ControlPersist` set.
- `${CLAUDE_SKILL_DIR}/scripts/afs-open-master.sh [host]` — open/reuse the Duo-free master.
- `${CLAUDE_SKILL_DIR}/scripts/afs-publish.sh <local_path> <remote_afs_dir> [remote_name]` —
  atomic publish for a single file (sibling `.new` then `mv`, refuses a symlinked target);
  `rsync` for a directory; ensures `system:www-servers read`; `AFS_PUBLIC=1` also grants
  `system:anyuser read`.

## Always-apply gotchas
- **tcsh on the far side:** wrap remote commands in `sh -c '…'` or pipe to `/bin/sh` (the
  scripts feed remote logic to `/bin/sh` on the remote for this reason).
- **`.htaccess` trailing newline** is mandatory.
- **macOS `ssh` lacks Duo-free `gssapi-keyex`** → no no-Duo *first* connection; reuse a
  persistent master (one Duo).
- **`kinit`/`aklog` are Duo-free**; AFS token ≈24 h, TGT ≈10 h, renewable ~7 d.
- **`security find-generic-password -w` appends a newline** — strip it before piping to `kinit`.
- **AFS ACLs are per-directory** (`fs la`, `fs sa . <who> <rights>`), not per-file.

## Safety
ACL changes and overwriting live web pages are outward-facing and hard to undo. Before
`fs sa`, overwriting an existing file, or removing `system:anyuser`, confirm the exact AFS
path and the change. For a WebAuth-protected directory, `system:anyuser` must have **no**
read — only `system:www-servers`.
