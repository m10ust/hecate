# Hecate

Guided three-corner backups for Omarchy.

One source. Three destinations that can fail independently. Versioned
snapshots. A bar mark that never claims protection it cannot evidence.

## The method

Three copies is the old rule. The part everyone skips is that the copies have
to be able to die for different reasons. Three folders on one disk is one
failure wearing three names. Hecate asks you for the source, then walks you
through three destinations, and it checks the physical device behind each one
before it lets a destination count.

The bar mark is three dots, one per corner, coloured by that corner's worst
status across every job. It never shows green for a corner it cannot vouch for.
If a destination is unmounted, the dot is amber with an age on it. If a read
fails, the dot is amber and the reason is in the panel. Unknown is a state, not
a pass.

## Install

```
omarchy plugin add https://github.com/m10ust/hecate.git --enable
```

To look before you leap, add it without `--enable`, read the source, then turn
it on. To remove it, `omarchy plugin remove io.github.m10ust.hecate`.

## How it runs

The wizard is the product. It asks for a source folder, then for three
destinations, and it does the checks out loud instead of assuming.

Destinations can be local paths, another machine over SSH, or a cloud remote
through rclone. Encryption is on by default and can be turned off in the wizard
or in settings.

Snapshots are versioned, not mirrored. Unchanged files are skipped by inode, so
the second run is cheap and the tenth run still knows what changed.

## What it touches

Hecate runs unsandboxed inside omarchy-shell, like every Omarchy plugin. Being
straight about the surface:

- `rsync` to write snapshots, over the transports above
- `ssh` when a destination is another machine
- `rclone` when a destination is a cloud remote
- `~/.local/state/hecate/state.json`, which the engine alone writes
- file manager pickers through Omarchy's own portal chooser
- an AIDE note where the lane is available, so a backup timer does not look
  like tampering to your integrity check

It does not ask for sudo, it does not install hooks, and the wizard never
writes state itself.

## Status

Pre-release. The code is verified by test suites in `tools/` and by hand on one
machine, and it has not been walked end to end on a second. Treat it as 0.x
until someone other than the author has restored from it.

## Design

The reasoning lives in `docs/`:

- `docs/PLAN.md` - the laws, the forks, and what was rejected
- `docs/WIZARD.md` - the six-step spine and why each step exists
- `docs/PROVIDERS.md` - how each destination kind gets onboarded

## License

MIT. See `LICENSE`.
