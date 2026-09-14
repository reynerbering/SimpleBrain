# My Second Brain

I dump raw stuff into `/raw`. AI turns it into clean notes in `/wiki`. That's it.

## Folders

- `/raw` — anything I capture: notes, PDFs, screenshots, links
- `/wiki` — clean notes written by AI
- `/archive` — processed `/raw` files land here so I can see what's been handled
- `/coding` — engineering notes and reusable orchestration prompts
- `/prompts` — standing prompts run against the vault
- `/tickets` — one file per Jira ticket

## The Loop

1. Write or drop anything into `/raw`.
2. Run an AI agent with the prompt in `prompts/translate.md`.
3. Read the updated `/wiki`.

The whole folder is a git repo, so nothing is ever lost.

## Stacks

What I work in. The `ship-tester` uses this shape to know how to run a suite — see [coding/four-agent-pipeline.md](coding/four-agent-pipeline.md).

**Resolution order.** A repo's own `CLAUDE.md` always wins. This is the fallback when a repo doesn't have one.

### C# / .NET

- Detect: `.sln` or `.csproj`
- Test: `dotnet test`
- Framework: match whatever the repo already uses — xUnit, NUnit, or MSTest. Never introduce a second one.

<!-- Fill in as they get decided: default target framework, solution layout conventions, anything non-obvious about running tests locally. -->

### Node / TypeScript

- Detect: `package.json`
- Test: the `test` script in `package.json`
- Package manager: from the lockfile. Never switch.

<!-- Fill in as they get decided: preferred runner (Jest/Vitest), monorepo tooling, default package manager for new repos. -->

### Per-repo overrides

If a repo needs something other than the above, put it in **that repo's `CLAUDE.md`**, not here. It travels with the code and works for teammates too.

```markdown
## Commands
- Test: <exact command>
- Build: <exact command>
- Lint: <exact command>
```
