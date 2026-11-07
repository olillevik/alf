---
name: git-commit
description: Create a concise git commit or commit subject from staged and unstaged changes compared with what is already committed. Use this skill for every request to commit, such as "commit this", "commit these changes", or "commit my work", or to write a commit message or subject from the current diff, not for release notes, changelogs, or PR summaries.
license: MIT
compatibility: Claude Code, GitHub Copilot CLI
---

# Git Commit

## What I do
- Check repository state and inspect staged and unstaged changes
- Read the current diff against what is already committed
- Draft a concise imperative subject that is easy to scan in `git log`
- Create a one-line commit by default when the user asks to commit

## When to use me
Use this skill when the user wants to commit current repository changes or wants a commit message based on the current diff. Check both staged and unstaged work before drafting the subject. Do not use it for release notes, changelog entries, or pull request summaries.

## Inputs or prerequisites
- A git repository
- Current changes in the worktree, index, or both
- A request to create the commit or draft its subject

## Workflow
1. Check context first.
   - Verify the directory is inside a git repository.
   - Check whether there are staged changes, tracked unstaged changes, or untracked files.
   - If there are no relevant changes, say so plainly instead of inventing a message.

2. Read the current diff for meaning.
   - If there are staged changes, read the staged diff.
   - If there are unstaged tracked changes, read the working tree diff too.
   - If there are untracked files, inspect enough context to understand whether they belong in the likely next commit.
   - Base the message on the functional change, not filenames alone.
   - Distinguish fixes, features, refactors, tests, docs, or maintenance only when the diff supports it.

3. Draft the subject.
   - Use imperative mood, a single subject line, and no trailing period.
   - Capitalize the first word.
   - Prefer a concise subject, ideally within 50 characters when that still says the real change.
   - Avoid file lists, vague filler, and speculative claims.
   - Return only the subject by default.
   - Do not add a body, trailers, metadata labels, code fences, or explanatory wrapper text unless the user explicitly asks for more than a subject line.
   - Prefer subjects that are easy to scan in `git log --oneline`:
     - start with a strong verb
     - name the thing that changed
     - add scope only when it helps locate the work
     - skip filler like `update`, `improve`, `changes`, or `stuff`

4. Either propose or commit.
   - If the user asked only for a message, return the subject and stop.
   - If the user asked to commit and there are staged changes, create the commit with `git commit -m "<subject>"`.
   - If the user asked to commit, nothing is staged, and the changes are tracked modifications or deletions only, create the commit with `git commit -am "<subject>"`.
   - If the user explicitly asks to amend the last commit, create the commit with `git commit --amend -m "<subject>"`.
   - Keep the commit message to one line by default.
   - Do not add another `-m`, a body, trailers, or any extra message text unless the user explicitly asks for a multi-line commit message.
   - If untracked files are part of the intended commit, stage them intentionally before committing instead of hiding them behind `-a`.
   - If multiple summaries are plausible or the user explicitly wants a body, show the proposed subject and ask before committing.

5. Check the result.
   - After committing, run `git log -1 --format=%B`.
   - If a trailer line appears, follow the "Trailers" section below.

6. Keep boundaries clear.
   - If the request also includes release notes, a changelog entry, or a PR summary, keep this skill focused on the commit.

## Trailers

Never add a trailer line to a commit message. That includes `Co-authored-by:`, `Signed-off-by:`, and any credit line for an AI tool or agent, even when a default, template, or tool asks for one. Commit with `-m` only.

If a trailer line is already in the message, amend with `git commit --amend -m "<subject>"`. Ask before amending a commit that is already pushed.

## Output expectations
- The default output is exactly one commit-subject line
- The subject matches the combined staged and unstaged diff the user is likely asking about
- Commits use a single-line subject by default
- Mixed requests keep commit work separate from release-writing work

## Examples
- "Commit my changes."
- "Write a commit message for what I changed."
- "Suggest a one-line commit message for the current diff."
- "What should this commit be called?"
- "Give me a commit subject for the staged and unstaged changes."
- Feature example: `Add auth check to POST /sessions`
- Bug fix example: `Fix nil panic in session cleanup`
- Refactor example: `Refactor session store setup`
- Avoid vague subjects like `Update auth` or wrapped output like `Suggested commit: ...`
