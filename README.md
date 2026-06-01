# Stanford AFS + WebAuth Website Guide

A practical, **Stanford-specific** guide to:

1. **Connecting to your AFS space over plain SSH/SFTP** — no OpenAFS client, no Fetch, no macFUSE.
2. **Hosting website content** in your AFS `WWW` directory (served at `https://web.stanford.edu/~sunetid/`).
3. **Putting that content behind WebAuth** and restricting it to specific people or **Stanford workgroups** via `.htaccess`.

It's written to be generic — replace `<sunetid>` with your own SUNet ID throughout.

---

> ## ⚠️ Deprecation notice — read this first
>
> Stanford is **sunsetting AFS for web hosting and file storage**. See:
> - [AFS service](https://uit.stanford.edu/service/afs) and [Publish a website](https://uit.stanford.edu/guide/website) (current/recommended options)
>
> This guide accurately documents the **AFS + WebAuth** path that still works today and serves the many existing AFS sites, but **for new projects prefer a [modern hosting option](https://uit.stanford.edu/guide/website/hosting).** A migration pointer is in [Part 6](#part-6--modern-alternatives).

---

## Table of contents

- [Prerequisites](#prerequisites)
- [Part 1 — Connect to AFS without special clients](#part-1--connect-to-afs-without-special-clients)
- [Part 2 — Host website content in AFS](#part-2--host-website-content-in-afs)
- [Part 3 — Protect content with WebAuth (`.htaccess`)](#part-3--protect-content-with-webauth-htaccess)
- [Part 4 — Authorize by Stanford workgroup](#part-4--authorize-by-stanford-workgroup)
- [Part 5 — Automating AFS publishing](#part-5--automating-afs-publishing)
- [Part 6 — Modern alternatives](#part-6--modern-alternatives)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Prerequisites

- An active **SUNet ID** (this gives you a UNIX account with an AFS home directory).
- **Duo two-step** enrolled (required for the login servers).
- A terminal. macOS and Linux have `ssh`/`sftp`/`scp`/`rsync` built in; on Windows use the built-in OpenSSH client (PowerShell) or WSL.

Your AFS home directory follows this layout (first two letters of your SUNet ID become the subdirectories):

```
/afs/ir/users/<1st letter>/<2nd letter>/<sunetid>
```

Example for `jdoe`:

```
/afs/ir/users/j/d/jdoe
```

---

## Part 1 — Connect to AFS without special clients

You do **not** need the OpenAFS client. The cleanest approach is to SSH into a Stanford login server that already has AFS mounted, and use the SSH/SFTP tools already on your machine. Stanford's **FarmShare** login nodes have direct AFS access at `/afs`.

### 1a. (Recommended) Add an SSH config alias with connection multiplexing

Multiplexing means you authenticate (password + Duo) **once**, and subsequent `scp`/`sftp`/`rsync` commands reuse that authenticated connection for a few minutes — no repeated Duo prompts.

Add this to `~/.ssh/config` (create the file if needed; `chmod 600 ~/.ssh/config`, `chmod 700 ~/.ssh`):

```ssh
Host farmshare
    HostName login.farmshare.stanford.edu
    User <sunetid>
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

### 1b. Log in

```bash
ssh farmshare
```

You'll be prompted for your SUNet password, then Duo (`Passcode or option (1-3):`). On first connect, verify the host key fingerprint matches Stanford's published values:

- **ED25519:** `SHA256:bKb1Znir/1tOg+TMyALDYWeK0lclsulriDN8aOvWteU`
- **RSA:** `SHA256:o5E5OOkaxwF+CzKT5A2/DNSmDzljTYs/a1V7Fm6ssSw`

> ℹ️ FarmShare's `HOME` is **not** AFS (it's separate NVMe storage). AFS is a distinct tree mounted at `/afs` on the login nodes.

### 1c. Confirm AFS access

```bash
ls -ld /afs/ir/users/<1>/<2>/<sunetid>
tokens                 # should list an afs token for ir.stanford.edu
```

On the FarmShare login nodes an **AFS token is usually granted automatically at login**. If you ever get *permission denied* under `/afs`, get a token manually:

```bash
aklog
```

### 1d. Transfer files (from your local machine)

These run on your laptop, not on FarmShare, and reuse the multiplexed connection:

```bash
# interactive browse / put / get
sftp farmshare

# copy a single file up
scp ./index.html farmshare:/afs/ir/users/j/d/jdoe/WWW/

# sync a whole folder (great for a site)
rsync -avz ./site/ farmshare:/afs/ir/users/j/d/jdoe/WWW/
```

See [`examples/ssh-config-snippet`](examples/ssh-config-snippet) for the config block.

---

## Part 2 — Host website content in AFS

### 2a. The `WWW` directory and your URL

Your AFS home contains a pre-configured **`WWW`** directory wired to the `web.stanford.edu` server. Content placed there is served at:

- `https://web.stanford.edu/~<sunetid>/`
- `https://<sunetid>.web.stanford.edu/`

```bash
cd /afs/ir/users/j/d/jdoe/WWW
# put your index.html and assets here
```

### 2b. AFS permissions (ACLs) primer

AFS access control is **per-directory** (ACLs apply to folders, not individual files). Two commands:

- `fs la` (alias for `fs listacl`) — list a directory's ACL
- `fs sa . <who> <rights>` (alias for `fs setacl`) — set rights (note the spaces: `sa` `space` `.` `space`)

Rights letters: **`rlidwka`**

| Letter | Meaning |
|---|---|
| `r` | read files |
| `l` | list / lookup directory |
| `i` | insert (create new files) |
| `d` | delete files |
| `w` | write / modify files |
| `k` | lock |
| `a` | administer (change the ACL) |

Common shorthands: `read` = `rl`, `write` = `rlidwk`, `all` = `rlidwka`, `none` = remove.

Special identities you'll use:

| Identity | Who it is |
|---|---|
| `system:anyuser` | literally everyone (anonymous, unauthenticated) |
| `system:authuser` | any authenticated AFS user |
| `system:www-servers` | the Stanford **web server** process (this is how the web server reads your pages) |

### 2c. Make `WWW` web-readable (public site)

For a **public** page, the web server must be able to read it:

```bash
cd /afs/ir/users/j/d/jdoe/WWW
fs sa . system:www-servers read     # let the web server read (rl)
fs sa . system:anyuser read         # optional: also browsable by anyone in AFS
fs la                                # verify
```

> If you intend to protect the directory with WebAuth, do **not** grant `system:anyuser` read — see Part 3.

---

## Part 3 — Protect content with WebAuth (`.htaccess`)

WebAuth restricts pages to authenticated **Stanford** people. Two pieces work together:

1. **AFS ACL** — the web server (`system:www-servers`) must be able to read the directory, but `system:anyuser` must **not** (so the only way in is through the authenticated web path).
2. **`.htaccess`** — Apache directives that require WebAuth login and define who's authorized.

### 3a. Set the ACL for a protected directory

```bash
cd /afs/ir/users/j/d/jdoe/WWW/private
fs sa . system:www-servers read     # web server can read
fs sa . system:anyuser none         # remove anonymous read
fs la
```

Expected result:

```
system:administrators rlidwka
system:www-servers rl
<sunetid> rlidwka
```

### 3b. Create the `.htaccess`

Put a file named `.htaccess` (note the leading dot) in the directory you want to protect.

**Any Stanford affiliate:**

```apache
AuthType WebAuth
require privgroup stanford:stanford
```

Other useful built-in privgroups: `stanford:student`, `stanford:faculty`, `stanford:staff`, `stanford:academic`, `stanford:administrative`.

**Specific people** (space-separated SUNet IDs):

```apache
AuthType WebAuth
require user jdoe gsmith lwilliams
```

**Combine** a group plus yourself:

```apache
AuthType WebAuth
require privgroup stanford:student
require user jdoe
```

See ready-to-copy files in [`examples/`](examples/).

> ⚠️ **Gotcha:** every directive line must end with a real newline (carriage return). A `.htaccess` whose last line has no trailing newline may be silently ignored.

### 3c. Test

- Open `https://web.stanford.edu/~<sunetid>/private/` in a fresh/incognito browser — you should be sent to WebLogin.
- Best test: have someone **not** authorized try to load it and confirm they're denied.
- Remember `.htaccess` is hidden — list it with `ls -a`.

---

## Part 4 — Authorize by Stanford workgroup

For anything beyond "all of Stanford" or a short list of names, use a **Stanford workgroup** as the authorization group.

### 4a. About workgroups

- Managed at **[workgroup.stanford.edu](https://workgroup.stanford.edu)** (the Workgroup Manager).
- Named `stem:id` — the **stem** before the colon identifies the owner, the **id** is the group name. Examples: `its:directors`, `gsb:affiliates`, and individual-owned `~jdoe:book_exchange`.
- Free for faculty, staff, and students with an active SUNet ID. A **new stem** is requested via a service ticket; you can then create groups under it.
- Workgroups can nest (a workgroup can contain other workgroups).

### 4b. Use a workgroup in `.htaccess`

```apache
AuthType WebAuth
require privgroup stem:name
```

Real-ish example restricting to a custom team plus the owner:

```apache
AuthType WebAuth
require privgroup ~jdoe:website-editors
require user jdoe
```

### 4c. Workgroup visibility / availability ⚠️

For a workgroup to be usable as a web-authorization privgroup, its **visibility settings** must allow the relevant systems to read its membership. If authorized members are unexpectedly denied, check the group's visibility in the Workgroup Manager — see [Workgroup Visibility Settings](https://uit.stanford.edu/service/workgroup/visibility) and [Restrict access to webpages using workgroups](https://uit.stanford.edu/service/workgroup/restrict).

---

## Part 5 — Automating AFS publishing

*(For scheduled/unattended writes — e.g. a cron or `launchd` job that rebuilds and republishes a site. New projects should prefer a [modern hosting option](#part-6--modern-alternatives); this is for keeping **existing** AFS sites fresh automatically.)*

Everything in Part 1 assumes you're at the keyboard to approve Duo. Automating writes adds two wrinkles: **FarmShare requires two-factor SSH**, and **Kerberos/AFS credentials expire**. The notes below were confirmed against `login.farmshare.stanford.edu` (an AuriStor cell) from macOS.

### 5a. You can't get a fully Duo-free SSH from a stock Mac

FarmShare's sshd requires **two** auth factors. A Kerberos ticket satisfies the first (`gssapi-with-mic`), but SSH reports only *partial success* and then demands a second from `gssapi-keyex`, `password`, or `keyboard-interactive` (Duo). The one second factor needing no human is **`gssapi-keyex`** (GSSAPI key exchange) — and **macOS's bundled `ssh` doesn't support it** (no `GSSAPIKeyExchange` option, and it rejects the `gss-*` KEX algorithms). So Duo is unavoidable for the *initial* connection.

**Pattern:** authenticate **once interactively** (one Duo) into a persistent multiplexed master, then let scheduled jobs reuse it:

```ssh
Host farmshare
    HostName login.farmshare.stanford.edu
    User <sunetid>
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials yes
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist yes          # keep the master alive (vs. a short idle timeout)
```

```bash
ssh farmshare true     # one Duo; opens the master — scheduled scp/ssh now reuse it
```

The master lives until the Mac reboots/sleeps or the network drops; then re-run that one-liner. A scheduled job can detect a dead master without hanging on a Duo prompt:

```bash
if ssh -o BatchMode=yes -o ConnectTimeout=10 farmshare true 2>/dev/null; then
    : # master alive — do the deploy
else
    : # master down — skip deploy, alert yourself to re-auth
fi
```

### 5b. Remote commands run under tcsh — wrap them in `sh -c`

FarmShare accounts default to **tcsh**, so a command sent as `ssh farmshare '…'` is parsed by tcsh, not a POSIX shell. Bourne syntax (`$(…)`, `2>/dev/null`, `VAR=val cmd`) fails — often with the cryptic `Illegal variable name`. Wrap remote commands:

```bash
ssh farmshare "sh -c 'aklog ir.stanford.edu 2>/dev/null; mv index.html.new index.html'"
```

### 5c. Kerberos is Duo-free; tokens expire

`kinit` talks to the KDC, where **Duo is not enforced** (Duo lives in the SSH/PAM layer). So you can mint tickets non-interactively — from a keytab, or by piping a stored password — then `aklog` for a token, all Duo-free:

```bash
# macOS Heimdal: read the password from a real file (not "STDIN"); forwardable + renewable
kinit --forwardable --renewable --password-file=<file> <sunetid>@stanford.edu
aklog ir.stanford.edu
```

macOS gotchas: `security find-generic-password -w` appends a trailing newline (strip it before piping); there's no `kvno` binary, so building a keytab is awkward — a Keychain-stored password + `--password-file` is usually easier. **Lifetimes:** AFS tokens ≈ 24 h, TGT ≈ 10 h, renewable ~7 days. For long-running automation, request renewable tickets and `kinit -R` to refresh (over a delegated master, run `kinit -R` on the *remote* side).

### 5d. If you'd rather mount /afs locally

The SSH dance exists to avoid a local AFS client. If you *do* want `/afs` mounted on the Mac (a job writes there directly, no SSH), Stanford's cell is **AuriStor**, so the supported client is **AuriStorFS** (a system extension), not legacy OpenAFS. Then `kinit` + `aklog` (both Duo-free) are all you need.

### 5e. Publish atomically

Update the live file atomically so viewers never see a half-written page: write a sibling `index.html.new`, then rename it over the target (`mv`/`rename` is atomic within an AFS directory). Reject a pre-existing symlink at the target so nobody can redirect the write.

---

## Part 6 — Modern alternatives

Because AFS web hosting is being retired, for **new** sites consider:

- **[Central / modern web hosting options](https://uit.stanford.edu/guide/website/hosting)** — choosing a current platform.
- Google Cloud / containerized apps behind **Stanford SSO** (a common pattern for newer Stanford apps).

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `permission denied` listing `/afs/...` | No AFS token — run `aklog`; check with `tokens`. |
| Page loads for *anyone* despite `.htaccess` | `.htaccess` not read — check the **trailing newline**, the filename (leading dot), and that it's in the served directory. |
| `403 Forbidden` for everyone, even authorized | Web server can't read the dir — `fs sa . system:www-servers read`. |
| Authorized workgroup member denied | Workgroup **visibility** doesn't permit web authorization — fix in Workgroup Manager. |
| Repeated Duo prompts for every transfer | Add the `ControlMaster`/`ControlPersist` block (Part 1a). |
| Can't see `.htaccess` | Use `ls -a` (dotfiles are hidden). |
| Remote `ssh farmshare '…'` fails with `Illegal variable name` | FarmShare's login shell is **tcsh**; wrap the remote command in `sh -c '…'` (Part 5b). |
| Automated SSH dies with `Permission denied (…keyboard-interactive)` | Two-factor required; stock macOS `ssh` can't do the Duo-free `gssapi-keyex`. Reuse a persistent `ControlMaster` opened once interactively (Part 5a). |
| Deploy works for hours, then `permission denied` under `/afs` | AFS token expired (~24 h) — refresh with `aklog` (and `kinit -R` for the ticket); see Part 5c. |

---

## References

- [Stanford AFS service](https://uit.stanford.edu/service/afs)
- [Navigating AFS](https://uit.stanford.edu/service/afs/intro/navigating) · [Setting permissions (UNIX)](https://uit.stanford.edu/service/afs/intro/permissions/unix)
- [Transferring files to AFS](https://uit.stanford.edu/service/afs/file-transfer)
- [FarmShare docs](https://docs.farmshare.stanford.edu/) · [Getting connected](https://docs.farmshare.stanford.edu/connecting/)
- [Publish a personal website (central hosting how-to)](https://uit.stanford.edu/service/web/centralhosting/howto_user)
- [Restricting access to web content (WebAuth)](https://uit.stanford.edu/service/web/centralhosting/webauth) · [Common WebAuth directives](https://uit.stanford.edu/service/web/centralhosting/webauth/directives) · [WebAuth with UNIX](https://uit.stanford.edu/service/web/centralhosting/webauth/unix)
- [Authentication & authorization](https://uit.stanford.edu/service/authentication)
- [Workgroups & the Workgroup Manager](https://uit.stanford.edu/service/workgroup) · [Restrict webpages using workgroups](https://uit.stanford.edu/service/workgroup/restrict) · [Workgroup visibility](https://uit.stanford.edu/service/workgroup/visibility)

---

*Community guide — not an official Stanford UIT publication. Verify specifics against the linked UIT documentation, especially as AFS/WebAuth are being retired. Corrections via PR welcome.*
