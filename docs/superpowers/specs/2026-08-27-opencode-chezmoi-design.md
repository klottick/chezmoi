# OpenCode chezmoi Integration

## Goal

Extend the existing chezmoi source repository with the portable, non-secret
parts of the user's OpenCode setup while preserving the current shell setup
and avoiding generated or credential-bearing files.

## Scope

The following files are managed by chezmoi:

- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/commands/rebase-dev.md`
- `~/.config/opencode/skills/rebase-against-dev/SKILL.md`
- The OpenCode executable path in `~/.zshrc`

The OpenCode provider configuration remains machine-specific. Its current
local vLLM endpoint and model values are kept as plain file content rather
than converted into chezmoi prompts or template data.

The following remain outside chezmoi:

- `~/.config/opencode/.env`
- `~/.config/opencode/node_modules/`
- `~/.config/opencode/package.json`
- `~/.config/opencode/package-lock.json`
- `~/.config/opencode/bun.lock`
- `~/.opencode/`, including the installed executable and runtime dependencies
- The unrelated fnm, Bun, and mise edits currently present only in `~/.zshrc`

## Source Layout

The source repository will use standard chezmoi path mapping:

```text
dot_config/opencode/opencode.jsonc
dot_config/opencode/commands/rebase-dev.md
dot_config/opencode/skills/rebase-against-dev/SKILL.md
dot_zshrc
```

`dot_config` maps to `~/.config`, and the `dot_` prefix maps to a leading
dot in the destination filename. No symlinks or copy scripts are required.

The process-only design document under `docs/superpowers/` is not a home
configuration target. The implementation will add `docs/` to
`.chezmoiignore` so the specification remains in the source repository
without becoming a managed `~/docs` tree.

The source `.chezmoiignore` will explicitly exclude the OpenCode secret,
package/runtime artifacts, and `~/.opencode/`. These exclusions are defense
in depth; the implementation will still add only the approved files rather
than recursively importing the whole OpenCode directory.

## Behavior

OpenCode will continue to load its global configuration, command, and skill
from `~/.config/opencode`. The executable remains installed separately under
`~/.opencode/bin`; managed zsh configuration will add
`$HOME/.opencode/bin` to `PATH` using the existing path-export style.

The OpenCode files can be applied selectively with:

```text
chezmoi apply ~/.config/opencode
```

The existing `panicOnExternalModifications = true` setting remains enabled.
Because `~/.zshrc` has unrelated external modifications, the implementation
must not use `--force` or overwrite the target blindly. The zsh source change
will be reviewed through `chezmoi diff`; reconciliation of the unrelated
fnm, Bun, and mise edits is out of scope.

The repository's `autoCommit = true` and `autoPush = true` settings must not
cause an implicit commit or push during this work. Source files will be
updated explicitly, and changes will remain uncommitted unless the user
requests otherwise.

## Verification

Verification will confirm that:

1. `chezmoi managed` includes exactly the three OpenCode files in addition to
   the existing managed entries.
2. The OpenCode target directory has no pending chezmoi diff after a targeted
   dry run or apply.
3. `opencode.jsonc` parses successfully, and the managed zsh source passes a
   zsh syntax check.
4. The source repository contains no `.env`, package metadata, lockfiles,
   `node_modules`, or `.opencode` runtime files.
5. The pre-existing `MM .zshrc` status is understood and remains protected;
   no forced target overwrite is performed.

## Non-Goals

- Installing or upgrading OpenCode, Bun, Node, or plugin dependencies
- Provisioning GitHub credentials or any other secret
- Making the local vLLM provider portable across hosts
- Reconciling unrelated shell changes
- Committing or pushing changes without an explicit request
