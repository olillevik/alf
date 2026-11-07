---
name: setup-alf
description: "Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills."
disable-model-invocation: true
---

Follow the skill in full at `../../upstream/mattpocock/setup-matt-pocock-skills/SKILL.md`. Read it first and do what it says, using the reference files beside it.

<!-- Local additions go between the markers. scripts/update-upstream.sh rewrites everything else. -->
<!-- overlay:start -->
## Steps

1. **Run the setup above, with these overrides:**
   - Override its file choice: the `## Agent skills` block goes to `AGENTS.md`, created if missing. Never write `CLAUDE.md`.
   - If `CLAUDE.md` already has an `## Agent skills` block, raise it at the confirm step and do not move it.

2. **Write the workflow into AGENTS.md.** Set `<root>` to the output of `git rev-parse --show-toplevel`. Stop and report if that command fails, or if `<root>/AGENTS.md` is a symlink.
   - Under `## Agent skills` → `### Issue tracker`, place the workflow block from the section below between its markers. If the markers already exist, replace everything from the start marker through the end marker. Otherwise insert the block after the `### Issue tracker` summary line. If either heading is missing, create it.
   - Done when each marker appears once and `### Issue tracker` appears once under `## Agent skills`.

3. **Report.** Tell the user the workflow block was added to `AGENTS.md`, and name any step that was skipped.

## Workflow block

Insert this block verbatim, without indentation:

```markdown
<!-- alf:issue-workflow start -->
- **Spec from an existing ticket**: add the spec to that ticket's body under a `## Spec` heading, replacing any existing `## Spec` section. Apply the label for the `ready-for-agent` role (see `docs/agents/triage-labels.md`).
- **Spec with no existing ticket**: create a new ticket for the spec.
- **Implementation tickets** (for example from `to-tickets`): create each one as a sub-issue of the ticket it was based on, the existing ticket or the spec ticket. With no such ticket, create standalone tickets.
- **Sub-issue operation**: if `docs/agents/issue-tracker.md` describes a sub-issue feature, use it. If the tracker has no sub-issue feature, or it is switched off (for example raw markdown files), link both ways by hand: the child's body starts with `Part of <parent>`, and the parent's body gets a `## Child tickets` checklist with one `- [ ] <child>` line per child. This overrides to-tickets' rule against modifying the parent, for these links only. Do not change the parent's open or closed state.
<!-- alf:issue-workflow end -->
```
<!-- overlay:end -->
