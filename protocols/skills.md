# Skills and Installers

> **Single source of truth.** Scope: **vault-only**.
> Linked (not imported) from `CLAUDE.md`. Do not restate it in `README.md`.

## Where skills come from

`/skills` holds all 48, and `~/.claude/skills` matches it exactly (verified 2026-09-15, both directions).

- **22 have an upstream.** They come from the `npx agents` installer, which writes to `~/.agents/skills`; a `SessionStart` hook (`~/.claude/sync-skills.sh`) copies that folder into `~/.claude/skills` on every session start. The hook runs **after** this vault's installer and overwrites those 22 with the upstream copy — so for them the vault copy is a versioned backup, not the live authority.
- **26 have no upstream** — the vault is their only copy: the 20 `aws-*` skills plus `amazon-bedrock`, `launch-with-aws`, `cloudwatch`, `investigate-ticket`, `playwriter`, `signing-in-to-aws`. Note that `amazon-bedrock` and `launch-with-aws` are AWS skills that do **not** carry the `aws-` prefix — don't reach for an `aws-*` glob to find this set.
- **`~/.agents/skills` actually holds 23, not 22.** The 23rd is `code-review`, and the hook's `EXCLUDE` list skips it deliberately so it cannot shadow Claude Code's built-in `/code-review`. It is intentionally absent from both `/skills` and `~/.claude/skills`. That exclusion is why 22 + 26 = 48 rather than 23 + 25.
- **To make the vault authoritative for all 48**, retire the `sync-skills.sh` hook and update the 22 by re-syncing `~/.agents/skills` into `/skills` and committing.

## The three installers

All vault-is-source: the vault is the authority, the installed copy is downstream. After a `git pull` that touches the source folder, re-run the matching installer.

| Installer | Installs | Re-run after a pull touching |
| --- | --- | --- |
| `skills/install.ps1` | `/skills` → `~/.claude/skills` | `/skills` |
| `coding/ship/install.ps1` | the four `ship-*` agents + `/ship` command → `~/.claude/` | `coding/ship/` |
| `user-memory/install.ps1` | `~/.claude/CLAUDE.md` → points at this vault | `/user-memory` |

`coding/ship/install.ps1` installs globally at the user level, so `/ship` works in every repo with nothing checked into any of them. `user-memory/install.ps1` resolves the vault path per machine, so it works from any checkout location.
