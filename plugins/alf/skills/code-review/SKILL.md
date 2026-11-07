---
name: code-review
description: "Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). Runs both reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to \"review since X\"."
---

Follow the skill in full at `../../upstream/mattpocock/code-review/SKILL.md`. Read it first and do what it says, using the reference files beside it.

<!-- Local additions go between the markers. scripts/update-upstream.sh rewrites everything else. -->
<!-- overlay:start -->
## Setup skill name

In this plugin the setup skill is `/setup-alf`. Wherever the instructions above name `/setup-matt-pocock-skills`, use `/setup-alf` instead.
<!-- overlay:end -->
