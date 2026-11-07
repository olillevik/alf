# Agentic Lifecycle Foundation

The `alf` skills give coding agents a baseline for software work. It covers setting up a repo, planning a feature, building it, fixing a bug, reviewing it, and improving how you work with agents. Most skills are popular community skills, vetted and kept up to date. Our own skills fill the gaps.

## Why alf

- **Proven skills first.** The base is community skills that many people already use: [mattpocock/skills](https://github.com/mattpocock/skills) and [humanlayer/skills](https://github.com/humanlayer/skills). Both are MIT licensed. We do not rewrite them.
- **Vetted before use.** Each upstream skill is copied at a pinned commit, scanned, and reviewed before it ships.
- **Updated without a full re-read.** A weekly job opens a pull request with what changed upstream. Reviewers read the diff, not the whole skill.
- **Extended without touching the upstream copy.** A wrapper holds your local instructions in an overlay. Updates keep the overlay.
- **Our own skills for the gaps.** `setup-github`, `git-commit`, and any in-house skills you add.
- **Flexible.** Install all of the skills, or only the ones you pick. Distributed with [APM](https://microsoft.github.io/apm/).

## Start here

- Not sure which skill fits? Run `/ask-alf`. It routes you to the right flow.
- Have an idea? Run `/grill-with-docs`. It interviews you about the idea and writes the glossary and decision records as terms and decisions get settled.
- The main flow, from idea to ship: `/grill-with-docs`, `/to-spec`, `/to-tickets`, `/implement`, `/code-review`, `/pr`. Then run `/retro` to suggest improvements to the agent's environment.

## What's included

| Need | Skills |
| --- | --- |
| Set up a repo | `setup-alf`, `setup-github`, `wizard` for steps only a person can do |
| Plan | `grill-with-docs`, `grill-me`, `to-spec`, `to-tickets`, `wayfinder` |
| Build | `implement`, `implement-spec`, `tdd`, `prototype` |
| Fix a bug | `diagnosing-bugs`, `tdd` |
| Review and ship | `code-review`, `pr`, `git-commit`, `triage` |
| Improve the architecture | `improve-codebase-architecture`, `codebase-design`, `domain-modeling` |
| Research and learn | `research`, `teach`, `show-me` |
| Improve how you work with agents | `retro`, `writing-for-agents` |
| Find your way | `ask-alf` |

`git-commit` and `setup-github` are in-house skills. The rest are upstream skills. The full list is in `plugins/alf/skills/`.

## Automated documentation

These docs are written or refreshed as you work with the skills and scripts:

- `/grill-with-docs` and `/domain-modeling` create `GLOSSARY.md` and `docs/adr/` as terms and decisions get resolved.
- `/setup-alf` writes the agent workflow block into `AGENTS.md`.
- `scripts/update-upstream.sh` regenerates each upstream's `PIN.md` and writes the body of each weekly pull request.

The skills do not generate general project documentation.

## How upstream skills stay safe

1. **Pinned.** Each upstream skill is copied at one commit. The upstream's `PIN.md` records that commit.
2. **Scanned.** `task ci` checks that `dist/` matches a fresh build, then runs SkillSpector on every skill and upstream skill, on each pull request and each push to `main`. After `task hooks:install`, it also runs before each commit. The scan is static and sends no file contents to an LLM. It fails on any MEDIUM, HIGH, or CRITICAL finding. To accept a finding, add it to `.skillspector-baseline.yaml` with a written reason.
3. **Reviewed as a diff.** A GitHub Actions job runs `task update-upstream` every Monday at 06:00 UTC. It moves unpinned skills to the latest upstream commit and opens a pull request. The pull request lists the moved skills, the commits between old and new, compare links, new upstream skills next to the copied ones, and any LICENSE changes. Later runs update the same open pull request.
4. **Held when you need it.** A pinned skill is skipped by the weekly update. Pin one with `task update-upstream SKILL=<name> REF=<sha or tag>`. Move it to latest with `task update-upstream SKILL=<name>`.

The scanner catches known risky patterns. It does not replace a reviewer.

## Extend an upstream skill

A wrapper is a skill that points at one upstream skill. To extend it, add your instructions between the `overlay:start` and `overlay:end` markers in the wrapper's `SKILL.md`. The update script keeps the overlay when it updates the upstream copy.

For example, the overlay in `plugins/alf/skills/ask-alf/SKILL.md` points `/setup-matt-pocock-skills` at `/setup-alf`.

## Add a skill

- **In-house skill:** create `plugins/alf/skills/<name>/SKILL.md` with `name` and `description` in its frontmatter. No upstream is needed. If the skill calls other skills by name, list them in `plugins/alf/skill-dependencies.txt`.
- **Upstream skill:** run `scripts/update-upstream.sh add <upstream> <url> <path>[=wrapper]`. The upstream repo must have a LICENSE on its default branch. The script copies the skill at its latest commit and writes the wrapper. Run `task build-apm`, review the result with `git status`, then commit it.

## Turn off skills

Delete the skill's line from your `apm.yml`, then run `apm install -g`. The skill is removed from `~/.claude/skills/`.

## Install

Install [APM](https://microsoft.github.io/apm/) first: `brew install apm`.

**One user, Claude Code**

Copy the manifest that lists every skill, then install:

```
mkdir -p ~/.apm
curl -fsSL -o ~/.apm/apm.yml https://raw.githubusercontent.com/olillevik/alf/main/dist/user-apm.yml
apm install -g
```

To update later, run `apm update -g`. To drop a skill, delete its line from `~/.apm/apm.yml` and run `apm install -g` again.

**A team**

List the skills in the team's `apm.yml`, each pinned to the same commit of this repo. List every skill that a listed skill calls by name too. `grill-with-docs` calls `grilling` and `domain-modeling`, so all three go in:

```yaml
dependencies:
  apm:
    - olillevik/alf/dist/skills/grill-with-docs#<commit sha>
    - olillevik/alf/dist/skills/grilling#<commit sha>
    - olillevik/alf/dist/skills/domain-modeling#<commit sha>
```

**GitHub Copilot CLI**

Not tested in this build.

## Development

- Install [go-task](https://taskfile.dev) (`brew install go-task`), [uv](https://docs.astral.sh/uv/) (`brew install uv`), and [jq](https://jqlang.github.io/jq/) (`brew install jq`).
- Run `task hooks:install` once per clone. After that, `git commit` runs `task ci` first and stops the commit if the scan fails.
- Run `task update-upstream DRY_RUN=1` to print the plan for an update without changing files.
- Run `task build-apm` after changing `plugins/alf/`, and commit `dist/` with the change. `task ci` fails when `dist/` is out of date.
- `plugins/alf/skill-dependencies.txt` lists the skills each skill calls by name, and the names it only mentions. The build fails when a skill names another skill that the file does not list.
- If the scan fails, see [docs/skillspector.md](docs/skillspector.md) for how to fix or accept each finding.
- `AGENTS.md` holds the rules agents follow when they change this repo.

## License

MIT. See [LICENSE](LICENSE). Each upstream folder keeps its own LICENSE.
