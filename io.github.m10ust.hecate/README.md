# Hecate (io.github.m10ust.hecate)

Three-corner backups, set up by being asked for them. Hecate Triformis —
the source is not a corner; corners one, two and three are destinations,
each with a transport (`local`, `ssh`, `rclone`), and the one hard rule is
independence: two partitions of one disk are not two corners, and neither
are two corners on one cloud account.

## Requirements

The Omarchy machine running the engine needs **Python 3.10 or newer**.
Check it with `python3 --version`. Older interpreters are rejected before the
engine evaluates its type annotations, with an explicit version requirement.

Python is not required on an SSH destination: the engine runs on Omarchy and
uses the destination's existing native tools. No dependencies are installed
by the plugin.

## Status: v0.0.3 — M3 (three corners + the independence check)

The data contract is the product law (PLAN.md, corrected 2026-09-30): **the
state file stores facts and the renderer classifies.** No stored `status`,
no stored `ageDays` — a stored verdict is one the file cannot re-derive, and
a machine that sleeps invalidates it silently. The five words
(`current` `away` `stale` `failed` `unknown`) are computed at display time
from `lastRun` + `horizonHours` + `override`, every render.

What is real in v0.0.3:

- **the engine** (`engine/hecate.py`): on-demand `rsync -a --numeric-ids
  --link-dest=<previous>` into `<dest>/hecate/<job>/<timestamp>/`, a
  `<timestamp>.latest` symlink flipped atomically after a successful run,
  verification by **file-list diff** (equal byte totals hide a swapped
  file), source `bytes`/`files` measured never estimated, and failures
  stored honestly as `override: {status: failed, reason: rsync's own
  words}` — a success is never written that was not observed
- **corners two and three are first-class.** Multiple corners per job,
  each with its own transport, destination, `horizonHours`, `lastRun`,
  `snapshot`, `verified`. Runs are per-corner: one corner failing never
  stops the others. `ssh` corners run the same rsync over ssh with
  `--link-dest` relative to the remote snapshot dir (rsync ≥ 3.1 on the
  remote; the wizard probes for it, M4)
- **the independence check (PLAN law 1) is a first-class engine function**,
  callable on demand (`hecate.py check <job>`, `check-fixtures <file>`),
  returning structured results — `pass` / `warn` / `refuse` / `unknown`,
  each finding with its reason and the evidence it used — never a boolean:
  - **hard refusal** when a destination resolves to the same filesystem as
    another corner or the source (same `st_dev`; same filesystem UUID is
    the stronger check where readable, and st_dev is not consulted when
    both UUIDs are readable — cross-host st_dev equality is spurious)
  - **overridable warning** for correlated failure that is judgement, not
    arithmetic: same model family on one power path (the two-Crucial
    lesson), two corners on one remote machine (one power path, one set
    of updates)
  - **cloud corners get a warning lane, never a refusal** — two remotes
    can alias one account (finding L1); declare-and-warn by nature
  - **unreadable identity is `unknown` with the reason, never a pass**
  - the same function gates `add-job`/`add-corner`: refusals block, warns
    need `--accept-warning`, and the acceptance is recorded in the state
    file (`independenceAck` with the date and the warning's own words)
- **the renderer** classifies at display time; a v1 state file (stored
  verdicts) classifies wholesale as `unknown` until the engine migrates it
- **`RUN NOW`** in the panel (and `qs ipc call io.github.m10ust.hecate
  run <job>`) triggers a run; nothing runs from the bar without a click
- local destination presence is probed (`test -d`) on the service's 30s
  clock: an absent destination renders `away`, not green
- the clock is in the QML dependency graph, so a corner goes stale on
  screen the minute it goes stale in fact
- wizard, systemd timers, rclone transport: M4+ (cloud needs its OAuth
  milestone, `PROVIDERS.md`)
- the manifest validates under `omarchy-plugin-validate`

Sandbox only through M3. The engine has not been pointed at any real
corpus (`~/Music`, the wiki, the Jarvis vault): the three-corner doctrine
exists because a catalog got lost, and the engine that implements it does
not rehearse on the originals.
