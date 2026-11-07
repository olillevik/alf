#!/bin/sh
# Scans each alf skill with SkillSpector, static only (no LLM).
# Fails on any active MEDIUM, HIGH, or CRITICAL finding, and on any scan that errors or is incomplete.
# A reviewer accepts a finding by adding it to .skillspector-baseline.yaml with a reason.
set -eu

SOURCE="git+https://github.com/NVIDIA/skillspector.git@v2.13.4"
BASELINE=".skillspector-baseline.yaml"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BLOCKING="$WORK/blocking.tsv"
: > "$BLOCKING"
status=0

# --baseline is rejected for recursive multi-skill scans, so each skill folder is scanned on its own.
# dist/ is not scanned here. Its bundles repeat these skills at shifted line numbers, and the
# baseline does not match them. `task ci` checks that dist/ matches a fresh build of these sources.
for skill in $(find plugins/alf/skills plugins/alf/upstream/mattpocock plugins/alf/upstream/humanlayer -mindepth 1 -maxdepth 1 -type d | sort); do
  [ -f "$skill/SKILL.md" ] || continue
  report="$WORK/$(echo "$skill" | tr '/' '_').json"

  if ! uvx --python 3.12 --from "$SOURCE" skillspector scan "$skill" \
      --no-llm --fail-on-incomplete --baseline "$BASELINE" \
      --format json --output "$report"; then
    echo "skillspector-ci: scan failed or incomplete: $skill" >&2
    status=1
    continue
  fi

  jq -r --arg skill "$skill" '.issues[]? | select(.severity == "MEDIUM" or .severity == "HIGH" or .severity == "CRITICAL") | [$skill, .severity, .id, .category, "\(.location.file):\(.location.start_line)"] | @tsv' \
    "$report" >> "$BLOCKING"
done

if [ -s "$BLOCKING" ]; then
  echo "skillspector-ci: active MEDIUM or higher findings (review, then accept in $BASELINE with a reason):" >&2
  printf 'skill\tseverity\tid\tcategory\tlocation\n' >&2
  cat "$BLOCKING" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "skillspector-ci: passed"
else
  echo "skillspector-ci: failed. See docs/skillspector.md for how to fix or accept findings." >&2
fi
exit "$status"
