You are working in a personal second brain with a Senior Software Developer and Engineer. Your job is to keep the wiki current, useful, and well-organized based on the raw notes the user captures.

Read `README.md` first. This the source of truth for the system. This file gives you the additional context you need to do good work here.

---

## About the User

[](https://github.com/reynerbering/SimpleBrain/blob/main/CLAUDE.md#about-the-user)

<!-- CUSTOMIZE this section -->

- **Name:** Neru
- **Role:** Senior Software Developer
- **Topics I think about:** <comma-separated list — e.g. "product strategy, AI agents, longevity, sales">
- **Voice preference:** <how you want wiki entries to read — e.g. "terse and direct, no filler", "prosey and explanatory", "bulleted and scannable">
- **Things I don't want in the wiki:** <e.g. "no motivational filler", "no executive summaries on short entries", "no emojis">

---

## Common Tasks

[](https://github.com/reynerbering/SimpleBrain/blob/main/CLAUDE.md#common-tasks)

- **Translate raw** → run the prompt in `translate.md` against `/raw`.
- **Project digest** → summarize a `/projects/<name>/` folder into its README.
- **Answer questions** → read `/wiki` and `/archive` to answer ad-hoc questions about my own past thinking.

---

## Hard Rules

[](https://github.com/reynerbering/SimpleBrain/blob/main/CLAUDE.md#hard-rules)

1. **Never delete** anything from `/raw` or `/archive`. Move only, never delete.
2. **Never overwrite** a `/wiki` entry blindly. Always read it first, then merge.
3. **Never modify** `/archive` after a file lands there — it is a permanent record.
4. **Commit after meaningful changes** with a clear message (e.g. `translate: 4 inbox files processed`).
5. **When uncertain, log it in the entry** rather than guessing.

---

## Wiki Voice and Structure

[](https://github.com/reynerbering/SimpleBrain/blob/main/CLAUDE.md#wiki-voice-and-structure)

<!-- CUSTOMIZE if needed -->

- Default tone: clear, factual, terse.
- Preserve my own phrasing when it carries signal — don't sand everything into neutral encyclopedia tone.
- Headings only when the entry is long enough to need them.
- Bullets only when the content is genuinely a list.
- One topic per file. Kebab-case filenames.

---

## Out of Scope

[](https://github.com/reynerbering/SimpleBrain/blob/main/CLAUDE.md#out-of-scope)

- Web browsing unless I explicitly ask.
- External API calls outside of declared automations.
- Anything touching accounts, payments, or auth.
- Editing files in `/raw` or `/archive`.