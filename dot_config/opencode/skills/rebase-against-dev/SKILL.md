---
name: rebase-against-dev
description: Use when a user asks to rebase a feature branch onto dev or origin/dev, synchronize a branch with dev, resolve rebase conflicts, or publish rewritten branch history.
---

# Rebase Against `origin/dev`

This is a guided executor for rebasing the current feature branch onto the
latest `origin/dev`. It may resolve conflicts semantically and repair direct
rebase fallout, but it must never guess about repository state or remote
history.

## Non-negotiable rules

- Operate on the currently checked-out, named branch only. Never check out a
  different branch. Refuse detached `HEAD`, the `dev` branch, or a branch
  whose upstream name is not the same as its local name.
- Require a clean worktree, including untracked files. Never stash, discard,
  reset, or create a WIP commit automatically.
- If any rebase, merge, cherry-pick, or revert is already in progress, stop
  and report it. Do not continue or abort it automatically.
- Always fetch `origin/dev` before a real run. If it is unavailable, stop.
- Refuse branches containing merge commits unique to the feature branch.
- Create a collision-free local backup ref before moving the branch tip. Keep
  its name and old SHA in the report. Delete it only after a successful push.
- Never use `git push --force`. Push only to the existing configured upstream,
  with an explicit `--force-with-lease`. If the upstream contains remote-only
  commits, stop instead of overwriting them. If there is no upstream, ask
  before rebasing and do not push unless an upstream already exists.

## Modes

- Normal: rebase, verify, and push automatically when all gates pass.
- `--no-push`: perform the local rebase and verification, but never push;
  retain the backup ref.
- `--dry-run`: perform no mutations at all. Inspect state and use
  `git fetch --dry-run origin dev`; do not update refs, create a backup,
  rebase, edit files, run checks, or push.
- Reject every other argument.

## Workflow

### 1. Preflight

Read the repository's `AGENTS.md`, `CONTRIBUTING.md`, and relevant project
documentation before choosing checks or regeneration commands. Then inspect:

```bash
git status --porcelain=v1 --branch
git status
git status --porcelain=v1 --untracked-files=all
git symbolic-ref --quiet --short HEAD
git branch --show-current
git rev-parse --abbrev-ref --symbolic-full-name @{upstream}
git remote get-url origin
```

The `--branch` status report always includes a `##` branch header; treat the
separate porcelain command without `--branch` as the dirty-worktree test and
require it to emit no lines. Stop for any dirty entry, an existing operation,
detached `HEAD`, `dev`, or an upstream that targets a different branch name.

After those local checks pass, fetch `origin/dev` and verify
`refs/remotes/origin/dev` exists. Then fetch the configured feature upstream as
well. Compare `HEAD...<upstream>`; if the upstream has commits absent locally,
stop and report them. Finally run `git rev-list --merges origin/dev..HEAD` and
stop if it finds merge commits unique to the feature branch.

If `HEAD` already equals `origin/dev`, report a no-op without creating a
backup, running checks, or pushing. If the branch has no unique commits and is
behind `origin/dev`, create the backup and fast-forward it with the rebase
operation, then continue through verification.

### 2. Rebase

Create a unique ref such as
`backup/rebase-against-dev/<branch>-<timestamp>` pointing at the old `HEAD`,
then run:

```bash
git rebase origin/dev
```

Do not use `--autostash`, `--rebase-merges`, blanket `ours`/`theirs`,
`git add -A`, or `git rebase --skip` without proving the commit is redundant.

For conflicts, inspect both sides and the repository guidance. Resolve the
actual intent; do not choose a side wholesale. Follow documented project
commands for generated SDKs, migrations, or other derived artifacts. If no
documented regeneration path exists, stop rather than hand-editing blindly.
Inspect `git diff --check` and the complete resolution, stage only resolved
paths, and run `git rebase --continue`. Continue automatically after a clear
semantic resolution; stop when intent or safety is uncertain.

### 3. Verify and repair

After the full rebase, require a clean status and confirm `origin/dev` is an
ancestor of `HEAD`. Detect targeted tests, lint, type checks, and build checks
from repository instructions and manifests; run them after the complete
rebase, not between commits. If no safe command can be identified, perform
Git-only verification (`git diff --check`, status, graph, and final diff) and
report that limitation.

Only repair failures directly caused by conflict resolution or regeneration.
Do not fix unrelated or merely co-located failures. Allow at most three
focused repair-and-check cycles. Record all repairs in one Conventional
Commit, for example `fix: resolve rebase fallout`; verify again afterward.
Stop if attribution is uncertain or checks still fail after three cycles.

### 4. Push and clean up

Unless `--no-push` was requested, refresh the configured upstream immediately
before pushing and re-check that it has not acquired remote-only commits.
Push the current branch to its existing upstream using an explicit lease for
the SHA observed by that final fetch:

```bash
git push --force-with-lease=refs/heads/<branch>:<observed-upstream-sha> \
  <upstream-remote> HEAD:refs/heads/<branch>
```

If the lease is rejected, stop and do not retry blindly. Delete the exact
backup ref only after the push succeeds; otherwise retain it for recovery.
Report the final SHA, checks, repair commit, push result, and backup status.

## Common mistakes

| Temptation | Required response |
|---|---|
| “Just start another rebase” while one is active | Stop and report the active operation. |
| “Stash it quickly” | Stop for the user to clean the worktree explicitly. |
| Choose `ours` or `theirs` for every conflict | Resolve each file from both sides’ intent. |
| Force-push because the user is in a hurry | Use only an explicit lease; stop on divergence. |
| Treat any failing test as rebase fallout | Fix only direct conflict/generated-artifact fallout. |
| Delete the backup before pushing | Retain it until push success is confirmed. |

## Recovery

Before a rebase completes, `git rebase --abort` restores the pre-rebase
checkout. After completion, use the reported backup ref to inspect or restore
the old tip. Never delete or overwrite a backup ref unless the exact ref and
intended recovery are confirmed.
