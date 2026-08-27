---
description: Rebase the current branch onto origin/dev using the guarded rebase workflow.
agent: build
---

Load and follow the `rebase-against-dev` skill for this request. Operate only
on the currently checked-out branch and reject any argument other than
`--dry-run` or `--no-push`.

Requested mode: $ARGUMENTS
