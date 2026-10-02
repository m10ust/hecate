# Hecate — provider authentication research

Compiled 2026-09-30. Question answered: **what does it take for a user to connect their
cloud account from inside the plugin?** Findings are receipted against primary sources
(rclone docs, Dropbox's own OAuth guide, Google's scope tiers). Where sources disagree,
both positions are stated.

---

## The headline: the plugin has to own its OAuth apps

The obvious shortcut is to lean on rclone's built-in authentication. Don't. rclone's bundled
client IDs belong to **rclone** — a user authorizing through `rclone config` is granting
access to *rclone's* registered application, not to Hecate. That is fine for a person in a
terminal, and wrong for a product with our name on it: it misrepresents who holds the
grant, and it is not a permission we have.

**So: register our own OAuth application per provider, run the authorization inside the
plugin, then hand the resulting token to rclone.** rclone accepts a pre-obtained token
non-interactively (the documented headless path is `rclone authorize` producing a token for
`config_token`, and `rclone config create` / `config update` take that token as a value).
`rclone` stays the transport engine; the plugin owns the identity layer.

**The verification burden is the real cost of this project.** Not the code.

---

## The flows available to a desktop plugin

| Flow | Needs a local listener? | Browser on same machine? | Paste involved? | Suits |
|---|---|---|---|---|
| **Loopback redirect** (127.0.0.1:PORT) | yes | yes | no | the cleanest UX where the provider allows it |
| **No-redirect code flow** | **no** | any | yes, short code | **best for a plugin wizard** — nothing to bind, no port, no conflict |
| **Device authorization grant** | no | any | user enters a code on a URL | TVs/limited-input devices; provider support varies per scope |
| **rclone's own flow** | yes (127.0.0.1:53682) | yes | no | not usable — see the headline above |

The **no-redirect code flow is the target** where a provider offers it: the wizard shows a
button, opens the provider's page, the user copies a short code back into the panel. No local
server, no port to collide with, nothing to firewall.

---

## Provider tiers

### Tier A — no OAuth at all (build these first)

These need endpoints and credentials, not an authorization dance. Cheapest to support, most
reliable, and the best failure behaviour.

- **S3-compatible** — Backblaze B2, Cloudflare R2, Wasabi, MinIO. Access key + secret.
  R2's zero-egress pricing makes it the natural "corner three" for nerds.
- **WebDAV** — one backend covering **Nextcloud**, ownCloud, Fastmail files and many others.
  This is the sovereignty lane: a user's own server, no vendor in the loop.
- **SFTP / ssh** — already in the plan.
- **SMB** — the NAS case, and it is the protocol Apple's own network backups use.
- **Mega**, **pCloud**, **Jottacloud**, **Storj**, **Filen** — credentials, no OAuth.

### Tier B — OAuth, friendly to a desktop app

- **Dropbox — the easiest real provider.** Dropbox's own docs: the `redirect_uri` is
  **optional** in the code flow, and "if unspecified, the authorization code is displayed on
  dropbox.com for the user to copy and paste to your app." That is exactly the wizard shape.
  PKCE is the recommended flow for desktop and open-source apps, so no client secret needs to
  ship in the binary. Use **App Folder** access rather than full Dropbox — least privilege,
  and a lower bar than a full-account app. Development apps need "additional users" enabled,
  and production use needs an app review; neither is a wall.
- **Microsoft OneDrive** — an Entra app registration, app-folder-scoped permissions for
  personal accounts. Familiar territory: the fleet already runs a consented Entra app for
  FSIEC mail, so this lane is known rather than theoretical. Consumer OneDrive is worth
  having purely for install-base size.

### Tier C — OAuth with a verification bill

- **Google Drive.** Here is what the sources actually say, and it is not friendly.

  **Scope choice decides everything.** `drive.file` (only files the app creates or the user
  opens) is the least-privilege path. Full `drive` is a **restricted** scope requiring a
  **CASA Tier 2 security assessment** before Google will even review — quoted between
  roughly $500–1,000 per year and "thousands, months-long", so treat it as expensive and slow.
  **Sources disagree on whether `drive.file` is non-sensitive or sensitive** (one claims
  non-sensitive: no verification, no warning, no user cap; others classify it as sensitive).
  Do not rely on the friendly reading without testing it on our own consent screen.

  **The blocker for a backup tool specifically:** an unverified app requesting
  sensitive/restricted scopes is capped at **100 users for the lifetime of the Google Cloud
  project — and that cap cannot be reset** (not by a new client ID, not by redeploying), and
  **test-mode refresh tokens expire after 7 days.** A backup corner that silently dies every
  seven days is worse than no corner, because it reads as green.

  **Verdict: Google Drive is not a v1 provider.** It becomes one only after our own OAuth app
  passes verification, and the plugin should say so in the provider list rather than offering
  a corner that will rot.

### Tier X — not viable

- **iCloud. No.** rclone does have an `iclouddrive` backend, and reading its own
  documentation kills the idea for a product:
  - It requires the user's **real Apple ID password plus 2FA** — "**app-specific passwords are
    not accepted**". Asking users to type their Apple ID password into our plugin is a
    non-starter for trust, and for Apple's terms.
  - It authenticates against the **reverse-engineered iCloud web interface** using a trust
    token and cookies, and the maintainer's own words are that the backend is "somewhat
    experimental".
  - It breaks when Apple changes things: the signin endpoint was deprecated and blocked
    (replaced only recently with an SRP implementation), **Advanced Data Protection accounts
    fail with HTTP 423** without a PCS-cookie fix, 2FA/trusted-number handling has
    open failures, and there is a case-sensitivity bug on Apple IDs.

  **Verdict: iCloud is not a Hecate corner, and the plugin should say why if asked.** The
  honest Apple-shaped corner is a Mac or NAS over SMB on the same network, or Time Machine to
  a network volume — both Apple-blessed and both already covered by transports we support.

---

## Recommended provider set

**v1.1:** Dropbox (the easy OAuth path), S3-compatible (B2 / R2 / Wasabi), WebDAV
(Nextcloud — the sovereignty lane), and OneDrive if the Entra registration is cheap to add.

**Later, after our own verification passes:** Google Drive.

**Never:** iCloud.

**And note the shape of this list:** the highest-value corners are all **Tier A** — no OAuth,
no review, no vendor gatekeeping. The providers that require an authorization dance are the
ones where a third party gets to decide whether our product is allowed to exist. That is worth
saying out loud in the plugin's own documentation, because it is the same argument as the rest
of the fleet: **own the transport, rent only the disk.**

## Sources

- rclone remote setup / headless authorization: https://rclone.org/remote_setup/
- rclone iCloud Drive docs (password + 2FA requirement, experimental status): https://rclone.org/iclouddrive/
- rclone PR #9209 (SRP signin, endpoint deprecation) and PR #9447 (ADP / PCS cookies, HTTP 423)
- Dropbox OAuth guide (optional redirect_uri, PKCE, App Folder access) and API docs
- Google OAuth scope tier / verification accounts, including the 100-user lifetime cap and
  7-day test-mode refresh expiry, and the CASA Tier 2 requirement for restricted scopes
