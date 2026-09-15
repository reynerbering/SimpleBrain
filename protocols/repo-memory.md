# Repo Memory Protocol

> **Single source of truth.** Scope: **travels** — it governs the `CLAUDE.md` files inside code repos.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

**Location:** `/wiki/repos/<TEAM>-<repo>.md` — e.g. `wiki/repos/CBS-CoreAPI.md`, `wiki/repos/AS-hosted-apply.md`.

- `<TEAM>` is `CBS` or `AS`. It is **not a Jira key** — repo memory has no ticket behind it. Never read it as one.
- `<repo>` is the exact on-disk folder name from the [`README.md`](../README.md) repo tables.

## The direction of truth

**The vault holds the content. The repo imports it.** Never the reverse — a copy in the vault goes stale the moment someone edits the repo, silently.

- Claude edits the vault note. The repo file is a stub that never changes.
- One place to read, one place to write, same folder. That is the whole point.

## Two shapes, decided by `git ls-files`

Check whether the repo's `CLAUDE.md` is tracked **before** touching it.

**Untracked (local to this machine)** — the whole file becomes a stub:

```markdown
# <repo>

Source of truth: SimpleBrain vault, wiki/repos/<TEAM>-<repo>.md

@C:/SimpleBrain/wiki/repos/<TEAM>-<repo>.md
```

**Tracked (shared with teammates)** — leave it completely alone:

- The tracked `CLAUDE.md` keeps owning the **team-facing** conventions. It is loaded from the repo as normal.
- Add a sibling `CLAUDE.local.md` holding only the import. Claude Code loads it right after `CLAUDE.md`.
- The vault note then carries **only the personal layer** (`layer: personal` in frontmatter), never a copy of the shared content.
- Anything the team needs goes into the tracked file through a normal PR — not into the vault.

**Why:** an `@C:/SimpleBrain/...` import resolves only on Neru's machine. Committing it would hand every teammate a file that silently loads nothing.

## Keeping the stub out of git

Use **`.git/info/exclude`**, not `.gitignore`.

- `.gitignore` is tracked — editing it pushes a machine-specific rule at the whole team.
- `.git/info/exclude` is local-only and invisible to everyone else.

## Frontmatter

On top of [the frontmatter contract](frontmatter.md):

| Property | Values |
| --- | --- |
| `type` | `repo-memory` — keeps these out of `wiki/design-docs.base`, which filters `type: design-doc` |
| `layer` | `personal` when the repo also has a tracked `CLAUDE.md`. Omit when the vault note is the whole thing |
| `consumed_by` | absolute path of the repo file that imports this note |

`team`, `repos` and `updated` follow the normal contract. `repos` is a list, always.

## Gotchas, verified against the Claude Code docs

- **`@path` imports accept absolute paths**, and nest to a **maximum depth of 4 hops**.
- **An import resolving outside the working directory triggers a one-time approval dialog** per project. Decline it and the imports stay disabled — and the dialog never reappears. Approve it the first time Claude Code opens each repo.
- **YAML frontmatter in an imported note is injected verbatim** into context. Keep it short.
- **Target under 200 lines** per memory file. Longer files measurably reduce adherence.
- Claude Code reads `CLAUDE.md`, not `AGENTS.md`.

## Adding a new repo

1. `git -C <repo> ls-files --error-unmatch CLAUDE.md` — decides which of the two shapes applies.
2. Write `wiki/repos/<TEAM>-<repo>.md` with the frontmatter above.
3. Write the stub (`CLAUDE.md` or `CLAUDE.local.md`) in the repo.
4. Append the stub's filename to `<repo>/.git/info/exclude`.
5. Commit the vault note. Nothing gets committed in the repo.
