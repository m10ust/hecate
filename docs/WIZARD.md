# Hecate — the wizard

Why this document exists: the copying is rsync and was never the hard part. **Getting someone
to set up three independent copies is the product.** Everything else in the plan serves this
flow. Seb's framing is the spec: the wizard asks for a destination for backup one, two and
three, and takes the user by the end to make it happen.

## Voice

Decided 2026-09-30. **Technical but easy for a newbie. Direct and to the point. No em dashes.**
No parenthetical asides, no colon-led reveals, no explaining the joke. The person reading this
may have never made a backup on purpose. Assume they are smart and new, not careless and
therefore to be scolded.

Every screen states what is true, what happens next, and what it will cost them. Nothing is
softened and nothing is hidden.

## The six steps

1. **Source** — pick the folder. Show size and file count *before* anything else.
2. **Corner one** — expected to be the local copy. Any transport allowed.
3. **Corner two** — where the independence check fires. This step earns the plugin its keep.
4. **Corner three** — ssh to a box they own, or a cloud remote through rclone with the
   no-redirect code flow (button opens the provider, user pastes a short code back).
5. **Schedule** — nightly by default, catch-up enabled.
6. **First run** — progress, closable, resumable, then a per-corner file-list diff as the
   receipt that the copies actually match.

## Three moments that decide whether it works

**The first run tells the truth about time.** Hundreds of gigabytes takes hours. It says so
before it starts, not after.

**The independence refusal is a hard stop with a reason.** This refusal is the thing no other
tool does, so it has to be explained rather than asserted. Hard stop for the same physical
device. Overridable warning for same model family or shared power path, because that is
judgement rather than arithmetic.

**An unplugged corner shows amber with an age.** It is the failure everyone actually has, and
it must never read as healthy.

## Re-enterable, not one-shot

The wizard is a live tool, not an installer. A drive dies two years in and the user needs to
point corner two somewhere else without rebuilding the job. Editing a corner, changing the
schedule and adding a second job are all first-class paths to the same screens.

## The copy (draft for Seb to cut)

**Opening**

> Hecate keeps three copies of a folder you choose, on three destinations that fail
> independently. Pick the folder first. You will see how large it is before anything else
> happens.

**Corner one**

> Where should the first copy live?
>
> A second drive is the fastest and the cheapest place to start. This is a default, not a rule.
> Any corner can be any kind of destination.

**Corner two**

> The second copy needs to survive whatever takes the first one.

**The refusal**

> That is the same physical disk as corner one. If that disk fails, you lose both copies at the
> same moment and you will not have a backup. Choose a different destination.

**The overridable warning**

> These two destinations look like siblings, so there is a real chance they fail together at the
> same age. Continue if you know why they are separate.

**Corner three**

> The third copy is the one that survives your house. A machine you own over ssh, or a cloud
> account.

**Schedule**

> Nightly at 02:00. If the machine was asleep, the next run catches up on its own.

**First run**

> The first copy takes hours, not minutes. 412 GB over USB will run for a while. You can close
> this panel. It resumes where it stopped.

**Finished**

> Three corners current. Last checked 2 hours ago.

**Not configured**

> Nothing is being protected on this machine yet. Choose a folder to begin.

**A corner that is not mounted**

> Corner 2 is not mounted. Its last successful run was 9 days ago. Plug it in, or point this
> corner somewhere else.

**A corner that failed**

> Corner 3 failed its last run. rsync exit 23, a file vanished mid copy. The other two corners
> are current.

**An encrypted cloud corner at setup**

> This corner will be encrypted before it leaves your machine. Your provider will store it and
> will not be able to read it.
>
> The key for that lives in your rclone configuration. Losing that file makes this corner
> unreadable forever, so Hecate keeps a copy of it in the other two corners.

**Re-entering**

> Swap a corner, change the schedule, or add a second job. Nothing here rebuilds what already
> works.

## Open question for M2/M4

Whether the wizard creates the job (and writes `state.json`) or the engine does, when the wizard
exits. The contract in `PLAN.md` is engine-written. The wizard should hand over a job
description and let the engine own the file, so there is exactly one writer.

## Status

Copy drafted 2026-09-30, not shipped. Seb cuts the wording. The screens come after M2, and the
engine can be built while this document is still being argued with.
