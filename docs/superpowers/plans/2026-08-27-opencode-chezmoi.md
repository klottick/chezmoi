# OpenCode chezmoi Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage the portable OpenCode configuration, custom command, custom skill, and shell PATH through the existing chezmoi source without importing secrets or runtime files.

**Architecture:** Use standard chezmoi source-name mapping under `dot_config/opencode/` for the three approved files. Add defense-in-depth ignore rules for secrets, dependency artifacts, the installed OpenCode runtime, and the process-only design/plan documents. Add the executable directory to `dot_zshrc`, but do not force-apply the drifted target shell file.

**Tech Stack:** chezmoi v2.62.2, Git, zsh, JSONC, Markdown

**Spec:** `docs/superpowers/specs/2026-08-27-opencode-chezmoi-design.md`

**Execution Worktree:** `/tmp/opencode/chezmoi-opencode` on branch
`feat/chezmoi-opencode`. Every chezmoi command in this plan must pass
`--source /tmp/opencode/chezmoi-opencode` so it cannot accidentally operate on
the original `main` checkout.

## Global Constraints

- Manage only `~/.config/opencode/opencode.jsonc`, `~/.config/opencode/commands/rebase-dev.md`, `~/.config/opencode/skills/rebase-against-dev/SKILL.md`, and the OpenCode PATH entry in `~/.zshrc`.
- Keep the current local vLLM endpoint and model values as plain machine-specific configuration.
- Keep `~/.config/opencode/.env`, package metadata, lockfiles, `node_modules/`, and `~/.opencode/` outside chezmoi.
- Add the OpenCode PATH as `$HOME/.opencode/bin` using the existing shell style.
- Preserve the existing `panicOnExternalModifications = true` setting.
- Leave the unrelated fnm, Bun, and mise edits currently present only in `~/.zshrc` untouched.
- Do not use `chezmoi apply --force`, `chezmoi re-add`, or any operation that silently overwrites the drifted `~/.zshrc`.
- Do not invoke the configured `autoCommit = true` or `autoPush = true` behavior through `chezmoi add` or `chezmoi edit`; use explicit Git commands for the requested commit and push.

---

## File Map

- Create: `dot_config/opencode/opencode.jsonc` - global OpenCode configuration, copied from the current target without template variables.
- Create: `dot_config/opencode/commands/rebase-dev.md` - global `/rebase-dev` command definition.
- Create: `dot_config/opencode/skills/rebase-against-dev/SKILL.md` - global rebase skill content.
- Modify: `.chezmoiignore` - exclude non-portable OpenCode/runtime files and source-only process documents.
- Modify: `dot_zshrc` - add `$HOME/.opencode/bin` to `PATH` near the existing path exports.
- Create: `docs/superpowers/plans/2026-08-27-opencode-chezmoi.md` - this implementation plan; it is source-repository documentation and must not become a home-directory target.

## Task 1: Add the Explicit OpenCode Allowlist

**Files:**
- Create: `dot_config/opencode/opencode.jsonc`
- Create: `dot_config/opencode/commands/rebase-dev.md`
- Create: `dot_config/opencode/skills/rebase-against-dev/SKILL.md`
- Modify: `.chezmoiignore`

**Interfaces:**
- Consumes: the existing files under `/home/klottick/.config/opencode`.
- Produces: three canonical chezmoi source entries that render to the existing OpenCode target paths.

- [ ] **Step 1: Confirm the source and target baseline**

Run from any directory:

```bash
chezmoi --source /tmp/opencode/chezmoi-opencode source-path
git -C /tmp/opencode/chezmoi-opencode status --short --branch
test ! -e /home/klottick/.config/opencode/.env
```

Expected:

- `chezmoi --source /tmp/opencode/chezmoi-opencode source-path` prints `/tmp/opencode/chezmoi-opencode`.
- The feature worktree is on `feat/chezmoi-opencode` with only the carried process-document files untracked before implementation.
- The removed `.env` file is absent.

- [ ] **Step 2: Add only the three approved target files to the source tree**

Use `apply_patch` to create the three source files with byte-for-byte content from their current targets:

```text
/home/klottick/.config/opencode/opencode.jsonc
    -> /tmp/opencode/chezmoi-opencode/dot_config/opencode/opencode.jsonc
/home/klottick/.config/opencode/commands/rebase-dev.md
    -> /tmp/opencode/chezmoi-opencode/dot_config/opencode/commands/rebase-dev.md
/home/klottick/.config/opencode/skills/rebase-against-dev/SKILL.md
    -> /tmp/opencode/chezmoi-opencode/dot_config/opencode/skills/rebase-against-dev/SKILL.md
```

Do not copy `.gitignore`, `package.json`, `package-lock.json`, `bun.lock`,
`node_modules/`, or any file under `~/.opencode/`. Do not introduce chezmoi
template expressions into `opencode.jsonc`.

- [ ] **Step 3: Add defense-in-depth ignore rules**

Append these exact entries to `.chezmoiignore`, preserving the existing
entries:

```text
.config/opencode/.env
.config/opencode/node_modules/
.config/opencode/package.json
.config/opencode/package-lock.json
.config/opencode/bun.lock
.opencode/
docs/
```

The final `docs/` rule keeps the design and implementation
documents in the source repository without mapping them to `~/docs`.

- [ ] **Step 4: Verify the allowlist before changing the shell source**

Run:

```bash
cmp /home/klottick/.config/opencode/opencode.jsonc /tmp/opencode/chezmoi-opencode/dot_config/opencode/opencode.jsonc
cmp /home/klottick/.config/opencode/commands/rebase-dev.md /tmp/opencode/chezmoi-opencode/dot_config/opencode/commands/rebase-dev.md
cmp /home/klottick/.config/opencode/skills/rebase-against-dev/SKILL.md /tmp/opencode/chezmoi-opencode/dot_config/opencode/skills/rebase-against-dev/SKILL.md
chezmoi --source /tmp/opencode/chezmoi-opencode managed --include=files /home/klottick/.config/opencode
```

Expected:

- All three `cmp` commands exit successfully.
- `chezmoi managed --include=files` lists exactly the three OpenCode target files under that directory, not `.env`, package artifacts, or runtime files.

## Task 2: Add Shell Wiring Without Overwriting Drift

**Files:**
- Modify: `dot_zshrc` near the existing `PATH` exports

**Interfaces:**
- Consumes: the externally installed executable at `~/.opencode/bin/opencode`.
- Produces: a managed shell export that makes executables in `~/.opencode/bin` available after a future deliberate zsh reconciliation.

- [ ] **Step 1: Add the managed PATH entry**

Use `apply_patch` to add this exact line to `dot_zshrc` alongside the existing
`PATH` exports:

```zsh
export PATH="$HOME/.opencode/bin:$PATH"
```

Do not import the target's hardcoded path comment or its fnm, Bun, or mise
blocks. The existing target already has an OpenCode path entry, so this source
change preserves the behavior while replacing the hardcoded form during a
future intentional apply.

- [ ] **Step 2: Syntax-check the managed zsh source**

Run:

```bash
zsh -n /tmp/opencode/chezmoi-opencode/dot_zshrc
```

Expected: exit status 0 and no syntax errors.

- [ ] **Step 3: Inspect, but do not apply, the drifted shell target**

Run:

```bash
chezmoi --source /tmp/opencode/chezmoi-opencode diff /home/klottick/.zshrc
chezmoi --source /tmp/opencode/chezmoi-opencode status
```

Expected:

- The diff shows the new managed `$HOME/.opencode/bin` export plus the existing differences for fnm, Bun, and mise.
- The pre-existing `MM .zshrc` status remains visible.
- No target shell file is changed, and no `--force` or `re-add` command is used.

## Task 3: Validate the Managed State and Target Mapping

**Files:**
- Verify: `.chezmoiignore`
- Verify: `dot_config/opencode/opencode.jsonc`
- Verify: `dot_config/opencode/commands/rebase-dev.md`
- Verify: `dot_config/opencode/skills/rebase-against-dev/SKILL.md`
- Verify: `dot_zshrc`

**Interfaces:**
- Consumes: the source entries produced by Tasks 1 and 2.
- Produces: evidence that only the approved OpenCode files are managed and that targeted application is safe.

- [ ] **Step 1: Parse the OpenCode configuration**

Run:

```bash
jq empty /home/klottick/.config/opencode/opencode.jsonc
```

Expected: exit status 0. The current file uses the JSONC extension but contains
valid JSON syntax, so no dependency installation is needed for this check.

- [ ] **Step 2: Preview the OpenCode-only application**

Run:

```bash
chezmoi --source /tmp/opencode/chezmoi-opencode diff /home/klottick/.config/opencode
chezmoi --source /tmp/opencode/chezmoi-opencode apply --dry-run --no-tty /home/klottick/.config/opencode
```

Expected: no OpenCode target changes, because the source entries match the
existing target files. The commands must not touch `~/.zshrc`.

- [ ] **Step 3: Apply only the OpenCode target set**

Run:

```bash
chezmoi --source /tmp/opencode/chezmoi-opencode apply --no-tty /home/klottick/.config/opencode
```

Expected: exit status 0 with no changes to package/runtime files or `~/.zshrc`.

- [ ] **Step 4: Verify final chezmoi state and exclusions**

Run:

```bash
chezmoi --source /tmp/opencode/chezmoi-opencode managed --include=files /home/klottick/.config/opencode
chezmoi --source /tmp/opencode/chezmoi-opencode status
chezmoi --source /tmp/opencode/chezmoi-opencode verify
git -C /tmp/opencode/chezmoi-opencode status --short --branch
```

Expected:

- `chezmoi managed --include=files ~/.config/opencode` lists exactly `opencode.jsonc`, `commands/rebase-dev.md`, and `skills/rebase-against-dev/SKILL.md`.
- `chezmoi status` has no new OpenCode entries and still reports the known `MM .zshrc` drift.
- `chezmoi verify` succeeds.
- Git shows the intended source changes and documentation only; there is no `.env`, package artifact, `node_modules`, or `.opencode` runtime file in the source tree.

## Task 4: Commit and Push the Feature Branch

**Files:**
- Commit: `.chezmoiignore`
- Commit: `dot_config/opencode/opencode.jsonc`
- Commit: `dot_config/opencode/commands/rebase-dev.md`
- Commit: `dot_config/opencode/skills/rebase-against-dev/SKILL.md`
- Commit: `dot_zshrc`
- Commit: `docs/superpowers/specs/2026-08-27-opencode-chezmoi-design.md`
- Commit: `docs/superpowers/plans/2026-08-27-opencode-chezmoi.md`

**Interfaces:**
- Consumes: the verified source changes from Tasks 1 through 3.
- Produces: a normal, non-force-pushed `feat/chezmoi-opencode` branch on `origin`.

- [ ] **Step 1: Review the complete intended diff before staging**

Run:

```bash
git status --short --branch
git diff --check
git diff --stat
git log --oneline --decorate -10
git remote get-url origin
```

Expected: only the approved chezmoi source, ignore rules, process documents,
and managed zsh change are present; no secret or runtime artifact appears.

- [ ] **Step 2: Stage only the approved paths**

Run:

```bash
git add .chezmoiignore dot_config/opencode dot_zshrc docs/superpowers
git diff --cached --check
git diff --cached --name-only
```

Expected: the staged path list contains only the files named in this task and
does not contain `.env`, package metadata, lockfiles, `node_modules/`, or
`.opencode/`.

- [ ] **Step 3: Create the requested Conventional Commit**

Run:

```bash
git commit -m "feat: manage OpenCode setup with chezmoi"
```

Expected: one new commit is created on `feat/chezmoi-opencode`.

- [ ] **Step 4: Push the feature branch normally**

Run:

```bash
git push --set-upstream origin feat/chezmoi-opencode
```

Expected: the branch is pushed without force, and its upstream is set to
`origin/feat/chezmoi-opencode`.

- [ ] **Step 5: Verify the pushed result**

Run:

```bash
git status --short --branch
git log -1 --oneline --decorate
git branch -vv
```

Expected: the worktree is clean, the branch tracks its pushed upstream, and
the final report includes the commit ID, push result, targeted chezmoi
verification, and the intentionally unresolved `MM .zshrc` drift.
