# SkillSpector checks

`task ci` scans every skill under `plugins/alf/` with SkillSpector and fails on any active MEDIUM, HIGH, or CRITICAL finding. CI runs the same task on every pull request.

When the check fails, read the log. Each line names the skill, the severity, the rule ID, and the file and line.

## Fix or accept

- Fix the finding when the skill is yours, under `plugins/alf/skills/`.
- Accept the finding when it is a false positive or a risk you accept.
- Don't edit files under `plugins/alf/upstream/`. They are upstream copies. Accept findings there.

## Accept a finding

1. Read the flagged line. Decide whether the finding is a false positive or a risk you accept.
2. Generate candidate entries outside the repo. Run this from the repo root:

   ```sh
   uvx --python 3.12 --from git+https://github.com/NVIDIA/skillspector.git@v2.13.4 skillspector baseline <skill-dir> -o <file-outside-repo> --no-llm --reason "<why it is safe>"
   ```

   `<skill-dir>` is the skill folder, such as `plugins/alf/upstream/mattpocock/to-tickets`.
3. Open the output file. Copy only the entry whose `rule_id` and `file` match the finding into `.skillspector-baseline.yaml`. Set its `reason` to one or two sentences that say why the finding is safe.
4. Run `task ci`. The finding no longer appears.
5. Commit the baseline change with your pull request.

The generated file lists every finding in the skill. Copy only the entries you accept.

## When an accepted finding returns

Each entry is tied to the SkillSpector version pinned in `Taskfile.yml` and to the exact file contents. A version bump or an edit to the file makes the finding active again. Repeat steps 2 to 5.

## Reviewer checklist

- The `reason` says why the finding is safe, in one or two sentences.
- The `rule_id` and `file` match the finding in the failing log.
- The pull request adds no entry for a finding the author did not show.
