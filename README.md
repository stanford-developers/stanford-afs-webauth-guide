# Stanford AFS + WebAuth Website Guide

A practical, **Stanford-specific** guide to:

1. **Connecting to your AFS space over plain SSH/SFTP** — no OpenAFS client, no Fetch, no macFUSE.
2. **Hosting website content** in your AFS `WWW` directory (served at `https://web.stanford.edu/~sunetid/`).
3. **Putting that content behind WebAuth** and restricting it to specific people or **Stanford workgroups** via `.htaccess`.

It's written to be generic — replace `<sunetid>` with your own SUNet ID throughout.

---

> ## ⚠️ Deprecation notice — read this first
>
> Stanford is **sunsetting AFS for web hosting and file storage**, and **WebAuth is being deprecated** in favor of **SAML / Shibboleth**. See:
> - [AFS service](https://uit.stanford.edu/service/afs) and [Publish a website](https://uit.stanford.edu/guide/website) (current/recommended options)
> - [WebAuth retirement announcement](https://uit.stanford.edu/service/saml/webauth-announce)
> - [SAML (Shibboleth)](https://uit.stanford.edu/service/saml)
>
> This guide accurately documents the **AFS + WebAuth** path that still works today and serves the many existing AFS sites, but **for new projects prefer a [modern hosting option](https://uit.stanford.edu/guide/website/hosting) with SAML.** A migration pointer is in [Part 5](#part-5--modern-alternatives).

---

## Table of contents

- [Prerequisites](#prerequisites)
- [Part 1 — Connect to AFS without special clients](#part-1--connect-to-afs-without-special-clients)
- [Part 2 — Host website content in AFS](#part-2--host-website-content-in-afs)
- [Part 3 — Protect content with WebAuth (`.htaccess`)](#part-3--protect-content-with-webauth-htaccess)
- [Part 4 — Authorize by Stanford workgroup](#part-4--authorize-by-stanford-workgroup)
- [Part 5 — Modern alternatives](#part-5--modern-alternatives)
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

## Part 5 — Modern alternatives

Because AFS web hosting and WebAuth are both being retired, for **new** sites consider:

- **[Central / modern web hosting options](https://uit.stanford.edu/guide/website/hosting)** — choosing a current platform.
- **[SAML / Shibboleth](https://uit.stanford.edu/service/saml)** — the supported successor to WebAuth. Authorization still maps to **workgroups**, so Part 4 knowledge carries over; the `.htaccess`/Apache config differs (Shibboleth + `Require shib-attr`/privgroup, typically set up by a site admin).
- Google Cloud / containerized apps behind **Stanford SAML SSO** (a common pattern for newer Stanford apps).

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

---

## References

- [Stanford AFS service](https://uit.stanford.edu/service/afs)
- [Navigating AFS](https://uit.stanford.edu/service/afs/intro/navigating) · [Setting permissions (UNIX)](https://uit.stanford.edu/service/afs/intro/permissions/unix)
- [Transferring files to AFS](https://uit.stanford.edu/service/afs/file-transfer)
- [FarmShare docs](https://docs.farmshare.stanford.edu/) · [Getting connected](https://docs.farmshare.stanford.edu/connecting/)
- [Publish a personal website (central hosting how-to)](https://uit.stanford.edu/service/web/centralhosting/howto_user)
- [Restricting access to web content (WebAuth)](https://uit.stanford.edu/service/web/centralhosting/webauth) · [Common WebAuth directives](https://uit.stanford.edu/service/web/centralhosting/webauth/directives) · [WebAuth with UNIX](https://uit.stanford.edu/service/web/centralhosting/webauth/unix)
- [Authentication & authorization](https://uit.stanford.edu/service/authentication) · [SAML / Shibboleth](https://uit.stanford.edu/service/saml) · [WebAuth retirement](https://uit.stanford.edu/service/saml/webauth-announce)
- [Workgroups & the Workgroup Manager](https://uit.stanford.edu/service/workgroup) · [Restrict webpages using workgroups](https://uit.stanford.edu/service/workgroup/restrict) · [Workgroup visibility](https://uit.stanford.edu/service/workgroup/visibility)

---

*Community guide — not an official Stanford UIT publication. Verify specifics against the linked UIT documentation, especially as AFS/WebAuth are being retired. Corrections via PR welcome.*
