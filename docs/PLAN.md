# Hecate — three-corner backups, set up by being asked for them

Status: PLAN (consolidation pass 1, 2026-09-30). No code until Seb signs off on the forks.
Name: Hecate — Greek goddess of crossroads and thresholds, keeper of the keys, and
**three-faced** (Hecate Trivia). In the older genealogies she is Scylla's mother.

---

## The thing that makes this a product

Not the copying. `rsync` has existed for decades, and so has every backup tool. The
actual barrier is that nobody refuses 3-2-1, they just never get around to it. So the
plugin's job is **to ask for the three destinations and then do the rest.**

Competing plugins in the Omarchy marketplace are status widgets: what your CPU is doing,
what CVEs affect your packages, whether your GPU fell off the bus. Twenty of them and
**not one touches where your data lives.** This is the same audience with a need none of
them serves.

## Four design laws (these are the product, not features)

1. **Corners must be provably independent.** When the user picks destination two, read
   the device identity (serial, model, filesystem UUID, mount source) and refuse to call
   it a corner if it resolves to the same physical device as another. Warn when two
   destinations share a model family and power path — the two-Crucial-drives lesson:
   same age and use profile means correlated failure. **The same logic applies to clouds:**
   two corners on the same provider, or the same provider *account*, share a failure domain
   (one suspension, one billing problem, one password reset kills both), so that gets the
   same warning. **Without this check you are adding copies, not corners.**
2. **Versioned, never a bare mirror, by default.** A plain mirror propagates the mistake:
   delete a file at the source and all three corners delete it next run. Use
   `rsync --link-dest` dated snapshots — unchanged files are hardlinked, so history costs
   almost nothing and a bad deletion is recoverable from yesterday's tree. Mirror mode is
   an explicit opt-in with a warning, never the default.
3. **An unmounted corner never reads as healthy.** The likeliest real failure is a drive
   in a drawer. Unmounted or unreachable renders amber with the age of the last
   successful run ("corner 2 not mounted · last run 9d ago"), never green, never silently
   skipped.
4. **Absence has three words.** Each corner reports current / stale / unknown. A read that
   failed is `unknown` and says why. Nothing is inferred to be fine.

## Guided setup (the wizard is the feature)

1. **What are we protecting?** Pick a source directory. Show its size and file count
   before anything else — the user should see what they're committing to. **The source is
   not a corner.** One source, three destinations.
2. **Corner one.** Usually the same-machine copy (a second drive, or a NAS share) because
   that's the cheapest and fastest first copy — but that's a *default, not a rule*: any
   corner may be any transport. Runs the independence check against the source's own
   filesystem.
3. **Corner two.** Same check, now against corner one. This is where the plugin earns its
   keep, because this is where people pick two partitions of one disk and call it two.
4. **Corner three.** Default offer: a cloud remote through `rclone` (Dropbox, Google Drive,
   and 70-odd other providers) **or** `ssh://user@host:/path` to a box they own. Both are
   first-class in v1 — the ssh corner is the sovereign one, the cloud corner is the one
   most people already pay for. A `git` remote is offered for text-shaped jobs only.
5. **Schedule.** Nightly by default, systemd user timer, `Persistent=true` so a machine
   that was asleep catches up.
6. **First run.** Show progress, allow closing the panel, rsync resumes. Then report the
   file-list diff per corner — the method that matters is **comparing the lists**, not
   byte totals, because equal sizes hide a swapped file.

## Folder selection — the click, not the path

Asked for by Seb 2026-09-30: when the wizard says "choose a folder", the user
clicks and gets the desktop's file chooser. Nobody should have to type
`/home/user/Music/Albums` from memory.

**The mechanism already ships on every Omarchy box.** `omarchy file select`
opens the desktop chooser through the XDG portal and prints the picked path to
stdout. It is a first-class Omarchy command, so using it adds no dependency at
all, which is the only version of this feature that can land on a stranger's
machine.

    omarchy file select --directory --title "Which folder do you want backed up?"

Its exit contract is already the shape we want, and the wizard should preserve it
rather than flatten it into success-or-failure:

| exit | meaning | what the wizard does |
|---|---|---|
| 0 | a path came back | continue to measuring |
| 1 | the user picked nothing | a decision, not an error — stay on the screen |
| 2 | the chooser never ran | a fault — offer the typed-path fallback and say which happened |

Two traps its own source documents, either of which would have cost an afternoon:
the portal answers with a **directed Response signal** addressed to the asking
connection, so a client that opens a connection and exits before the answer
arrives never hears it (which is why Omarchy's implementation is a long-lived
Python process rather than a `gdbus call`), and it **times out after 600
seconds**, so a caller must not wait forever on a dialog nobody answered.

**The source** uses the folder chooser. **A local destination** uses the same
one — a mounted drive is just a path, so this covers the drive case too. **A
remote destination** (`ssh`, `rclone`) cannot use a chooser at all; that path
stays typed, and the wizard should say why rather than showing a dead button.

**Pair the information with the choice, not with the picker.** After a
destination is chosen, show what it actually is: `omarchy-drive-info` plus our
own identity probe between them know brand, capacity, free space, and for a real
device the serial. Two 1TB drives in a drawer are identical as path strings and
completely different as that line, and the independence check needs the device
identity anyway. There is also an `omarchy-drive-select` TUI listing drives with
space and brand, but it renders in a terminal, so it is not a panel control —
its value here is the information, not the widget.

Invoke it at `/usr/share/omarchy/bin/omarchy` with a `command -v omarchy`
fallback: the path is a stable-by-design constant on Omarchy (same reasoning as
`127.0.0.53` for the resolver), and the fallback costs nothing if a future
Omarchy moves it.

## Engine

- **Copy:** `rsync -a --numeric-ids --link-dest=<previous>/ --info=progress2`
- **Snapshots:** `<dest>/hecate/<job>/<timestamp>/` with `<timestamp>.latest` symlink
- **State:** one JSON per job, `<state>/hecate/<job>.json` — per corner: status, last
  successful run, file count, total bytes, list-diff result, device identity
- **Schedule:** `systemd --user` timer per job; failures surface through the widget
- **Scope:** user data only in v1. No root, no system paths.

## UI

- **Bar glyph:** one character plus colour. Green three-of-three current; amber if any
  corner is stale/unknown/unmounted; red if a job failed or a corner is missing a
  snapshot chain.
- **Panel:** per job, the three corners as rows with age, size, and the last diff result.
  Click a corner for its snapshot list. A "verify now" action that re-runs the list diff
  without copying.
- **Nothing runs from the bar without a click.** Observe and report; the human triggers.

## Risks and honest limits

- **First run is the scary one** — hundreds of GB takes hours. Progress + resumability.
- **A corner that is an extern drive will be offline often.** Designed for, but it means
  "3/3 current" is not the normal state for most users. The panel should make the *reason*
  obvious so amber doesn't become noise.
- **rsync over ssh needs keys, not passwords.** Setup must detect and say so plainly.
- **v1 has no restore UI.** Restoring means browsing a snapshot directory. That's honest
  but incomplete, and it's the first thing v2 adds.
- **Retention:** v1 keeps everything. A pruning policy (keep last N + one per month) is
  needed before this is safe on small drives; without it, link-dest trees still grow.

## Test plan (on the live fleet)

1. Run it on the music corners that already exist — rig copy, Crucial drive, bee. If the
   widget reports three current and I verify that by file-list diff independently, it
   works.
2. Deliberately point corners two and three at two partitions of the same physical disk
   and confirm it **refuses** to call them corners.
3. Unplug a corner and confirm the widget goes amber with the age, not green.
4. Delete a file at the source, run again, confirm it survives in yesterday's snapshot.
5. Break ssh (bad key) and confirm the corner reads `unknown` with the reason, not failed
   silently.

### The dogfood sequence (decided with Seb, 2026-09-30)

Three runs, each proving a different thing. Do not collapse them — the small one
is not a rehearsal for the big one, it is the only one you can check by hand.

1. **The correctness run: `~/Pictures` on the rig — 120 MB in 21 files.**
   Small enough to verify every file by hand, which is the whole point. This is
   where the tool has to prove it tells the truth: refuse a corner that shares a
   device, catch a byte corrupted without changing the file's length, resume
   after the machine sleeps. Minutes, not hours.
2. **The scale run: `~/Work` — 8.3 GB across 79,220 files.** Light in bytes,
   heavy in files, so it exercises the per-file path rather than throughput.
   Expect tens of minutes. Note it is already Syncthing-mirrored, so a success
   here proves the engine rather than proving the backup was needed.
3. **The real-data run: the music library, ~30 GB.** Not an endurance test —
   `~/Work` is the scale test in this set, at 79,220 files. This is the run where
   the data is irreplaceable, so it is the one where a mistake actually costs
   something. It is also where the cloud corner's cost question gets its first
   honest number: at 30 GB even a naive cloud layout is cheap, which means the
   Part C decision matters far more for a stranger with 400 GB than it does here.

Ruled out as a first job: the rig's `~/Documents`, at 5.5 MB in two files, is too
little to prove anything.

**Sizing note (Seb, 2026-09-30):** *"if it works with one gigabyte, I don't see
why it wouldn't work with 400."* Correct as stated, for everything that matters
to correctness — refusal, byte verification, the manifest and the resume logic are
all scale-invariant. Three things are not, and none of them is a cliff:

1. **An interrupted first run.** A 400 GB copy cannot finish between sleeps, so
   crash-and-resume becomes the normal path rather than an edge case, and a run
   that resumes five times must not corrupt its manifest. At 1 GB that path never
   executes. Test it deliberately: kill a run mid-flight and resume it.
2. **The free-space gate.** The "warn below three times the source" rule can
   never fire on a 1 GB job and fires constantly on a 400 GB one.
3. **Cloud cost.** At 30 GB even a naive full-copy-per-snapshot layout is
   affordable. At 400 GB that choice *is* the design. This is economics, not
   correctness, which is why it only decides Part C.

So the small run does not need to become a big one to close these. It needs the
interruption forced and the gate exercised.

**Correction (2026-09-30):** this section first said the music library was 412 GB.
That figure came from `firstRunTruth` in `Strings.js`, which is placeholder copy,
not a measurement. The library is ~30 GB (`~/Music/CYTEK-Logic` alone is 26.4 GB
across 2,061 files). That string must not ship carrying a number nobody measured
— see the copy note below.

## AIDE and systemd user units (found 2026-10-01)

The rig's AIDE watch treats `~/.config/systemd/user/**` as a watched path, and
the check correctly flagged `/home/m4/.config/systemd/user/timers.target.wants`
on 2026-10-01 (directory mtime moved at 22:54; the alert carries the check time,
00:15, not the change time). **Hecate installs systemd user timers**, so on any
box running AIDE, enabling a timer is a tamper alert. That is not a bug in either
tool, it is two correct tools meeting.

Two consequences, and they are different in kind:

**For the user's box.** The engine should announce what it is about to touch
before it touches it. Where AIDE is present, run `aide-note` naming every path
the install writes, before the write, then refresh. Where AIDE is absent, say so
and move on. Never install a silent service on someone's machine — this is the
zero-cross doctrine applied to the installer, and it is also just good manners.

**For the alert stream.** Directory-only churn in that path is a known class and
should be filtered at the *consumer*, never in a rules file (a local rules file
makes the shipped rule fatal and the service exits). But the filter must be
narrow: a **directory** row alone is information, any **file** row inside that
directory is a finding, because a new unit file is exactly what user-level
persistence looks like. Filtering the whole path would blind the layer to the
one thing it is there to catch.

## M5.5 (addendum brief, 2026-10-01): picker, announce implementation, backing-disk key

Three additions from the addendum, all shipped in v0.0.6:

**The folder picker** rides `omarchy file select --directory` (the portal
chooser that already ships on every Omarchy box) rather than building a second
one. Its exit contract is preserved, not flattened: 0 = a path came back
(stdout is local paths — the engine converts portal URIs), 1 = the user picked
nothing (a decision, not an error — the screen stays), 2 = the chooser never ran
(a fault — the typed-path fallback names which happened). Exit 0 without
exactly one absolute path is a fault too. The 600s dialog timeout lands as
nothing-picked. A remote (ssh) corner cannot use a chooser and the screen says
why instead of showing a dead button. Live fact: `Gio` finds the session bus
via `$XDG_RUNTIME_DIR/bus` even without `DBUS_SESSION_BUS_ADDRESS`, so on any
desktop session the chooser opens for real — the wizard's process plumbing
inherits a working bus, and the fault lane only exists on true headless seats.

**The AIDE announce, and the lying lane.** Implemented in the engine:
`write_job_timer` announces every path the install touches (unit pair + the
`timers.target.wants` directory + the enable symlink — aide-check greps
literally, so a note naming some but not all paths adjudicates nothing) BEFORE
the write, attempts `aide-note`, and records how the announcement traveled
(`announce: noted | degraded | absent` + cause) in the timer facts and stdout.
THE TRAP, receipted live: unprivileged `aide-note` exits 0 printing "noted @"
while stderr carries Permission denied and nothing lands (`/var/lib/aide/notes`
is root-700). The exit code and stdout are both lies; the only trustworthy
signals are the notes-dir probe and the note READ-BACK after the call. When the
lane is closed the announcement degrades to stdout (journald for timer runs)
plus the state file, and says which happened. Teardown announces too — the
2026-10-01 00:15 alert was fired by a removal, not an install.

**The backing-disk key.** The bee has one btrfs root: `/` is
`/dev/mapper/root[/@]` (st_dev 32) and `/home` is `/dev/mapper/root[/@home]`
(st_dev 30) — one disk, one UUID, two st_dev, because every btrfs subvolume
gets its own anonymous device id. st_dev inequality would pass both as
independent corners. The UUID lane already refuses this pair, but a UUID-less
read must not slip through: `backed_disk_key` (UUID first, else the mount
source with the `[/subvol]` suffix stripped) now sits between the UUID lane and
the st_dev lane in `same_filesystem`. Fixture `independence-bee-onedisk.json`
strips the UUIDs and refuses through the new lane with the subvolume words in
the evidence. On the bee itself every corner for an on-bee job must be another
machine — the tool refuses to call the bee's own root disk two corners, which
is the deployment's cleanest test case (Seb's call: the bridge folder is the
first thing to protect, 34 MB / 87 files).

**Capacity pairing** (addendum §1, pair the information with the choice):
`check-destination` now carries `capacity` in its JSON — the step-0 measured
source size (passed via `--source-bytes`, never re-walked per corner) paired
with the destination's measured free space: pass (>=3x), warn (<3x), refuse
(zero free), unknown (either side unreadable — never a silent number). The
wizard renders it under the device identity line.

**The firstRunTruth string** (addendum §4): the proposal ships as
`firstRunTruthDraft` (labelled, bracketed, with the measured {size}
substituted) rendered beside the still-live old string on the first-run screen
— Seb compares both in place; his word flips which one ships. Nobody measured
412 GB and the number must not survive on its own authority.


## Findings accepted from the v0.0.1 review (Windy, 2026-09-30)

Raised against the 15:27 PLAN.md snapshot; all eight **accepted**. Recorded here with the
disposition rather than rewriting the sections above, because the sections get rewritten at
M2 brief time and this list is the thing that must not be lost.

- **H1 — the crypt config is in no job's source, and the plan resolved it circularly. ACCEPTED,
  and it is worse than stated.** Default-on encryption makes `rclone.conf` critical data, and
  for a one-source-per-job user that file is inside no source — so the key to corner three is
  protected by nothing. The finding is broader than the crypt case: **every rclone credential
  lives in that one file** (Dropbox token, S3 keys, WebDAV password). Resolution: the wizard
  **refuses an rclone corner unless a config job exists**, and the config job protects
  `rclone.conf` plus Hecate's own state, riding corners 1 and 2. This ships in v1, not as a note.
- **H2 — amber permanence defeats law 3. ACCEPTED.** If amber is the normal state, users learn
  "amber means fine", which is the alert-fatigue disease this fleet already knows from AIDE.
  Resolution: a fourth presentation — **green-with-a-notch** for away-and-expected, and **amber
  only** when a corner is past its **own horizon** or has never completed a run. Horizon is
  per-corner, not global: a nightly job is stale at 48 h, a drive used occasionally at 45 days.
- **M1 — absence has four words, not three. ACCEPTED.** The vocabulary becomes `current`,
  `away` (expected absence with a known last run — remediation: plug it in), `stale` (past its
  horizon), `failed` (mounted but erroring — remediation: read the error), and `unknown` (the
  read itself failed). Conflating any two hides the one thing the panel exists to say.
- **M2 — the cloud verify story is weaker than the plan presents. ACCEPTED.** `rclone sync
  --backup-dir` yields current state plus dated orphaned files — there is **no tree-as-of-date**
  to diff against, so "verify now" on a cloud corner verifies the present, not the history.
  Rename churn registers as delete+create and quietly doubles cloud delta. The plan must state
  what a cloud corner can and cannot prove, and no UI may promise point-in-time restore.
- **M3 — ssh to a Mac is a fleet-relevant trap. ACCEPTED, and it touches our own boxes.**
  macOS ships openrsync (Sequoia+) or ancient rsync, where `--link-dest` is not dependable —
  and the fleet's own third box is a Mac mini. The ssh corner requires **rsync ≥ 3.1 on the
  remote** and the wizard probes for it, or versioning degrades silently.
- **L1 — refusal vs warning. ACCEPTED.** Law 1's hard refusal is enforceable for local corners
  (device identity); for cloud it is declare-and-warn plus alias detection by inspecting
  `rclone.conf`. The plan's "refuses to count it as a corner" overclaims for clouds.
- **L2 — precedence was implicit. ACCEPTED.** Evaluation order fixed: **red > amber > green**.
- **L3 — the retention warning is the weakest one. ACCEPTED.** Keep-everything in v1 stands, but
  a one-time 3× warning does nothing at month six. **Per-corner fill fraction in the panel**, so
  approaching-full is visible before it is a failure.

Her build receipts are in `~/Work/hecate/receipts/` on the rig: validator clean on both copies,
a pixel-scanner she wrote to prove the glyph colours with cross-talk checked at zero, and panel
OCR. Note for the install lane: **the validator refuses symlinks**, so repo→plugins is
copy-then-diff.

## Data contract (corrected 2026-09-30, per Windy's P1)

**A stored `status` is a verdict the file cannot re-derive, and a machine that sleeps
invalidates it silently.** Writing `current` at 02:10 and sleeping a week produces a green
glyph that is a lie, which is law 3's disease arriving through the file instead of the glyph.
So the contract stores facts and the renderer does the classification.

```json
{
  "version": 2,
  "writtenBy": "hecate v0.0.2",
  "jobs": [
    {
      "name": "music",
      "source": { "path": "/home/m4/Music", "bytes": 26400000000, "files": 2061 },
      "corners": [
        { "index": 1, "transport": "local", "destination": "/mnt/backup/music",
          "lastRun": "2026-09-30T02:10:00-04:00", "horizonHours": 48 },
        { "index": 2, "transport": "ssh", "destination": "bee:/srv/corners/music",
          "lastRun": "2026-09-21T02:10:00-04:00", "horizonHours": 48,
          "override": { "status": "failed", "reason": "rsync exit 23: file vanished" } },
        { "index": 3, "transport": "rclone", "destination": "dropbox:hecate/music",
          "lastRun": null, "horizonHours": 48 }
      ]
    }
  ]
}
```

Rules:

- **What `verified: true` actually means today.** It means the post-run **file-list and size**
  comparison passed. It does **not** mean the bytes match. Krogh's original threat list for 3-2-1
  includes **transfer corruption**, and a file corrupted in transit with an unchanged size would
  pass our current check. Content verification (checksums, or `rsync -c`) is an **M5 item** and
  until it lands, no screen may claim the copies are identical — only that the lists agree. This
  is the same discipline as the rest of the contract: say precisely what was measured.
- **The renderer classifies.** `current` if the age of `lastRun` is inside `horizonHours`,
  `stale` if past it, `away` if the destination is expected-absent with a known `lastRun`,
  `failed` if `override.status` says so. Never trust a stored verdict for anything the clock
  can decide.
- **`override` exists only for what the clock cannot know** — `failed` (with its `reason`) and
  `unknown` (the read itself failed). It never carries `current`.
- **`ageDays` is computed from `lastRun`, never stored.** A stored derivative is a frozen
  derivative, and it was my error to put it in v1's contract.
- **`horizonHours` is per-corner.** A nightly job is stale at 48 hours; a drive someone plugs
  in twice a month wants something closer to 1080. One global threshold would lie about one of
  them.
- **Vocabulary is five words:** `current`, `away`, `stale`, `failed`, `unknown`.

## Transports (added 2026-09-30 at Seb's request)

**Provider authentication research: see `PROVIDERS.md` in this directory.** Headline
finding: the plugin must register its **own** OAuth applications rather than leaning on
rclone's bundled client IDs, and the verification burden — not the code — is the real cost
of supporting OAuth providers. iCloud is not viable as a corner, Google Drive is not a v1
provider, and the highest-value providers (S3-compatible, WebDAV) need no OAuth at all.

A corner is not always a path. Four transports, one plugin:

| Transport | Corner type | Versioning | Verification |
|---|---|---|---|
| `local` | a second drive or NAS share | `--link-dest` hardlinked snapshots | file-list diff |
| `ssh` | a box you own (`user@host:/path`) | `--link-dest` hardlinked snapshots | file-list diff |
| `rclone` | Dropbox, Google Drive, OneDrive, S3, 70+ providers | `rclone sync --backup-dir=<dated>` | `rclone check` (hash-verified) |
| `git` | text, config, dotfiles | the commit itself | `git fsck` + tree hash |

**Hardlinked snapshots do not survive a cloud sync.** Dropbox and Drive have no concept
of a hardlink, so a link-dest tree uploaded there becomes a full copy per snapshot —
storage explosion, and Dropbox ignores symlinks so the `.latest` pointer breaks too. So
cloud corners use a different mechanism, and it's a better one for them:

**`rclone sync --backup-dir=<dated>`** archives only the files that were *replaced or
deleted*, server-side. History costs exactly what your changes cost, which is the right
shape for a cloud corner. Optionally `rclone crypt` for client-side encryption — the
sovereignty-compatible cloud corner — with the honest trap attached: **the crypt config
becomes critical data in its own right**, because losing it makes the corner unreadable.
It needs its own corner.

**GitHub is not a bucket.** A git remote is the cleanest possible third corner for text:
inherently versioned, diffable, verified by `git fsck` and the tree hash, and free. It is
also the wrong corner for media — 100 MB per file and repo size limits — so the plugin
should refuse based on measured size rather than letting a user discover it via a failed
push. Right corner for dotfiles, configs and documents; wrong corner for the music
library. That's a v1.1 job type, not a v1 transport.

**Note on Dropbox specifically:** you already caught it uploading with an empty folder,
and the finding was that a sync client is never idle. `rclone`'s Dropbox backend avoids
the official client entirely (which is also the one that officially doesn't support
non-ext4 Linux filesystems), so a cloud corner here is `rclone push`, not a daemon
holding your home directory.

## Open forks for Seb

1. **Transports in v1:** `local` + `ssh` + `rclone` (one dependency covering Dropbox,
   Google Drive and 70 more). `git` as a v1.1 job type for text and dotfiles. Confirm?
2. **Job scope:** one source directory per job, or several? (I recommend one.)
3. **Retention:** keep everything, or add a keep-N policy before publishing? Cloud corners
   get their history a different way — `--backup-dir` archives only what changed — so this
   mostly matters for local and ssh link-dest trees.
4. **Publish timing:** dogfood on the fleet first, then publish, or ship and iterate in
   public? (I recommend dogfood first — you'd catch the amber-noise problem before
   strangers do.)
5. **Encryption — DECIDED 2026-09-30.** Default **on**, toggleable off in both the wizard
   and settings. One caveat the wording implies but doesn't state: **flipping it later is
   not a free switch.** An encrypted cloud corner stores opaque blobs with obfuscated
   names, so turning encryption off for an existing corner means a new remote layout and a
   full re-seed. Design: the toggle applies per job at creation, and changing it later
   offers to **re-seed into a new corner and keep the old one until the new one verifies**
   — never renames or overwrites in place. The wizard says that out loud, once, at the
   moment the user touches the switch.

**Adopted defaults (my recommendations, unless you object):** transports local + ssh +
rclone (git in v1.1), one source per job, dogfood on the fleet before publishing.
**Still genuinely open:** retention in v1. Proposal: v1 keeps everything and the setup
warns on drives smaller than 3× the source — the pruning policy arrives in v2 with the
restore UI, because doing retention without restore is the wrong order.

## Distribution (Seb's stated end goal, 2026-09-30)

**"The end goal is for this to run on anyone who is running Omarchy."** So distribution is a
requirement, not an afterthought, and it changes what matters.

- **The repo goes public.** The marketplace fetches it, so `io.github.m10ust.hecate` flips from
  the fleet's private habit to public, with the usual history sweep before the first push.
- **No sudo, anywhere.** The whole thing is user-level: no system paths, no root, no services
  outside `systemd --user`. A backup tool that needs privileges to install is a backup tool most
  people never install.
- **Dependencies are detected and named, never assumed.** rsync ≥ 3.1 (the ssh corner probes the
  remote, per M3's finding), rclone only once cloud corners exist. If something is missing, the
  user gets the install line for their distro instead of a failure.
- **The README teaches the method, not just the commands.** Seb's framing, 2026-09-30: **"We'll
  teach people how to do backup the Scylla way."** That is stronger than "document the tool", and
  it is achievable because every part of the doctrine is a *checkable property* rather than a
  preference: independence is provable from device identity, versioning is provable by a deleted
  file surviving in an earlier tree, absence is visible as amber with an age, and a state file
  cannot lie after a sleep because the renderer classifies from `lastRun` instead of trusting a
  stored verdict. 3-2-1 has been best practice for twenty years and almost nobody implements the
  independence half, because the implementer has to be willing to refuse the user. A policy
  cannot refuse. A tool can. **The enforcement is the lesson.**
- **The tool teaches without policing.** A setup that is genuinely unsafe is refused. A setup
  that is merely questionable can be continued, and the decision is recorded as
  `independenceAck` in the state file — a fact about a human choice. Nobody is stopped from
  doing it their way, and nobody gets to pretend afterwards that the tool recommended it.
- **The README also carries the limits.** No cloud tree-as-of-date, no restore UI in v1, no
  retention policy yet. Stated plainly and early, because a backup tool that overpromises is
  worse than one that scopes itself.
- **Semver and a CHANGELOG**, like bar-glow.
- **Support is the adoption risk, and honesty is the mitigation.** The refusal that names its
  evidence, the amber that carries an age and a reason, the `unknown` that says why it could not
  read — every one of those answers a user's question before it becomes an issue. That property
  is a product feature, not an implementation detail.
- **A backup tool gets exactly one chance with a stranger's data.** The sandbox discipline does
  not stop at the milestones. It ships after it has run on our own real corpora for a while, and
  the dogfood pass is a gate rather than a formality.

## M5 verdict — the cloud corner (2026-09-30, Windy's answer to Oracle's Part C)

**A cloud can be a corner, it cannot be all three** — adopted as law, in
Oracle's words, into the wizard's future copy (Seb approves the wording).

**Versioning on object storage: `--backup-dir`, not content-addressed
objects.** The reasons, graded against rclone's actual behaviour:

1. Content-addressing buys perfect point-in-time reconstruction, but Hecate
   already has that story for the OTHER two corners via link-dest trees, and
   a cloud corner's job under 3-2-1 is survival of the house, not archival
   browsing. Reconstruction-from-graveyard being "work rather than a
   listing" is acceptable for the corner whose failure scenario is
   "everything local is gone".
2. The keyed-hash (HMAC) requirement is the real cost multiplier: it makes
   every manifest check a keyed operation, forces key management (a second
   critical secret that itself needs a corner — the H1 disease again), and
   the confirm-oracle property it buys (attacker can't test guesses) is
   defense against a threat (someone holding the corner and guessing
   filenames) that encryption-on-by-default already blinds. With crypt on,
   names are obfuscated anyway; guessing "does file X exist" against an
   encrypted, name-obfuscated remote is already near-zero signal.
3. `--backup-dir` is one code path: `rclone sync` + one flag. It needs no
   second layout, no upload existence check, no per-provider name-mangling
   logic to debug. For a v1 plugin whose distribution law is "works for
   anyone on Omarchy, no sudo", the simpler mechanism wins until field use
   demands more.
4. Rename churn doubling cloud delta (M2's finding) stands as a documented
   limit of the chosen mechanism, stated in the README-to-be, not a reason
   to switch.

**Verification mapping: use the provider checksum where one exists and is
content-derived; otherwise say `size+mtime` in the basis field and render
"checked by size and date, content unverified".** Corrections to the
proposal's mapping, verified against rclone's backend docs:

- Dropbox's content_hash is SHA-256 over 4 MB blocks — rclone surfaces it
  as the file's hash, but it is NOT plain sha256: a corner scrub cannot
  compare it against a locally computed sha256sum. It verifies transfers
  (`rclone check` against the crypt/remote pair), it does not port into
  our MANIFEST format.
- S3's ETag = MD5 only for non-multipart uploads; the multipart boundary
  is size- AND configuration-dependent (upload_cutoff, chunk sizes), so
  "large files" is not even a stable predicate. ETag must be treated as
  unusable unless the backend is known single-part — i.e. basis
  `provider-checksum` only where rclone itself reports a hash type of
  `md5`/`sha1` AND the file is known non-multipart, else `size+mtime`.
- OneDrive/Drive (SHA-1/MD5) are genuine content hashes rclone can
  fetch — `provider-checksum` is honest there, with the SHA-1-is-weak
  caveat recorded (a corrupted copy that collides SHA-1 passes; that is
  a birthday-attack-sized "if", stated rather than hidden).
- Crypt layering: with encryption on (the default), provider checksums
  are of the CIPHERTEXT. `rclone check` between local plaintext and a
  crypt remote works (rclone re-encrypts to compare); a direct
  MANIFEST-vs-provider-hash comparison does not. So the cloud scrub is
  `rclone check`, not our sha256 walk — the basis note says which ran.
- Safer default adopted: when in doubt, `size+mtime` + the honest render
  string. No rounding up.

**Independence: three clouds = one failure mode.** The wizard's
cloud-corner screen will carry this in plain words (Seb's approval), and
the independence check's cloud finding (L1) already declares-and-warns
per cloud corner; two cloud corners on one provider/account get the same
warning lane as two ssh corners on one host (same power-path precedent,
different evidence words).

**The honest headline for the README:** a cloud corner carries a weaker
guarantee than a local one, and the panel will say so — `size+mtime`
basis renders differently from `bytes`. Parity is not implied; the
difference is visible. Testing without accounts: rclone local-dir
remotes exercise the whole lane (Oracle's own suggestion — agreed, and
it is how the cloud lane will be tested when it is built).

## Milestones

- **M1** manifest + Service + BarWidget skeleton, installs and renders (no engine).
- **M2** engine: one source, one corner, rsync + link-dest, state file.
- **M3** corners two and three + the independence check.
- **M4** the guided wizard.
- **M5** systemd timers + catch-up + the verify action. **DONE 2026-09-30
  (v0.0.5):** per-job user timers with Persistent=true (live-fired, journald
  receipt), run lock, MANIFEST.sha256 inside every snapshot, basis-not-verdict
  verification, the scrub verb that catches the length-preserving flip
  (receipted on local AND ssh corners), collision handler on both transports,
  per-corner capacity facts. Cloud verdict written (section above); cloud
  code zero.
- **M6** dogfood on the music corners, fix what the real runs teach.
- **M7** `omarchy-plugin-validate`, README, LICENSE, repo `io.github.m10ust.hecate`.

## Naming note

Hecate holds the keys and stands at the crossroads with three faces looking three ways.
The name is the doctrine. The repo id would be `io.github.m10ust.hecate` under the
marketplace convention.
