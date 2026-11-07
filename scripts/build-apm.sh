#!/usr/bin/env bash
# Builds one self-contained APM skill bundle per skill into dist/skills/, and dist/user-apm.yml,
# the manifest a single user copies to ~/.apm/apm.yml. Run by `task build-apm`.
# `--check` builds into a temp folder and fails if dist/ differs from it. CI runs it.
# Never edit dist/ by hand. See AGENTS.md.
#
# Written for bash 3.2 (macOS /bin/bash): plain variables, loops and case only.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$REPO_DIR/plugins/alf"
UPSTREAM_DIR="$PLUGIN_DIR/upstream"
SKILLS_DIR="$PLUGIN_DIR/skills"
DEPS_FILE="$PLUGIN_DIR/skill-dependencies.txt"
DIST_DIR="$REPO_DIR/dist"
ALF_REPO="olillevik/alf"
OVERLAY_START='<!-- overlay:start -->'
OVERLAY_END='<!-- overlay:end -->'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: scripts/build-apm.sh [--check]\n' >&2
  exit 2
}

# Frontmatter of a SKILL.md, from line 1 through the closing ---.
frontmatter() {  # SKILL.md
  awk '{ print } NR > 1 && /^---$/ { exit }' "$1"
}

# Everything after the closing --- of a SKILL.md.
body() {  # SKILL.md
  awk 'seen { print } !seen && NR > 1 && /^---$/ { seen = 1 }' "$1"
}

# The overlay block of a wrapper, markers included.
overlay() {  # SKILL.md
  awk -v s="$OVERLAY_START" -v e="$OVERLAY_END" '$0 == s { on = 1 } on { print } $0 == e { exit }' "$1"
}

# The upstream skill a wrapper points at, as slug/skill. Prints nothing for an in-house skill.
upstream_ref() {  # SKILL.md
  grep -o '`\.\./\.\./upstream/[^`]*/SKILL\.md`' "$1" | head -n 1 \
    | sed 's#^`\.\./\.\./upstream/##; s#/SKILL\.md`$##' || true
}

# Names of the skills in plugins/alf/skills/, sorted.
list_skills() {
  local d
  for d in "$SKILLS_DIR"/*/; do
    if [[ -f "$d/SKILL.md" ]]; then
      basename "$d"
    fi
  done
}

# The names listed under a key in plugins/alf/skill-dependencies.txt, space-separated.
# Key is a skill (its dependencies) or "<skill> mentions" (its mentions).
names_for() {  # key
  [[ -f "$DEPS_FILE" ]] || return 0
  awk -v n="$1" '
    /^#/ || !/:/ { next }
    { key = $0; sub(/:.*/, "", key); gsub(/^ +| +$/, "", key) }
    key == n { val = $0; sub(/^[^:]*:/, "", val); gsub(/^ +| +$/, "", val); print val; exit }
  ' "$DEPS_FILE"
}

# Dependencies a skill declares, space-separated.
deps_for() {  # skill
  names_for "$1"
}

# Names a skill mentions without calling, space-separated.
mentions_for() {  # skill
  names_for "$1 mentions"
}

# Regex that matches a skill name used as a call: /name, `name`, "name", 'name', or "name skill".
name_pattern() {  # name
  local n="$1" pat
  pat="(^|[ (])/${n}([^A-Za-z0-9/_-]|\$)"
  pat="$pat|\`${n}\`|\"${n}\"|'${n}'|(^|[^A-Za-z0-9/_.-])${n} skill"
  printf '%s\n' "$pat"
}

# Writes dist/skills/<skill>/ into the output folder: the whole upstream folder, the wrapper's
# frontmatter, the upstream body and the overlay. In-house skills are copied as they are.
build_skill() {  # skill out
  local skill="$1" out="$2" src dest ref slug up deps dep
  src="$SKILLS_DIR/$skill"
  dest="$out/skills/$skill"
  mkdir -p "$dest"
  ref="$(upstream_ref "$src/SKILL.md")"
  if [[ -z "$ref" ]]; then
    cp -R "$src/." "$dest/"
  else
    slug="${ref%%/*}"
    up="$UPSTREAM_DIR/$ref"
    [[ -f "$up/SKILL.md" ]] || die "$src/SKILL.md points at $ref, which does not exist"
    grep -q "$OVERLAY_END" "$src/SKILL.md" || die "$src/SKILL.md has no overlay markers"
    cp -R "$up/." "$dest/"
    cp "$UPSTREAM_DIR/$slug/LICENSE" "$dest/LICENSE"
    {
      frontmatter "$src/SKILL.md"
      printf '\n'
      body "$up/SKILL.md"
      printf '\n'
      overlay "$src/SKILL.md"
    } > "$dest/SKILL.md"
  fi
  deps="$(deps_for "$skill")"
  if [[ -n "$deps" ]]; then
    {
      printf 'name: %s\nversion: 1.0.0\ndependencies:\n  apm:\n' "$skill"
      for dep in $deps; do
        printf '    - %s/dist/skills/%s\n' "$ALF_REPO" "$dep"
      done
    } > "$dest/apm.yml"
  fi
}

# Writes dist/user-apm.yml, which lists every skill for a single user.
write_user_manifest() {  # out
  local out="$1" skill
  {
    printf 'name: alf\nversion: 1.0.0\ntargets:\n  - claude\n'
    printf '  # - copilot   # not tested yet\n'
    printf 'dependencies:\n  apm:\n'
    for skill in $(list_skills); do
      printf '    - %s/dist/skills/%s\n' "$ALF_REPO" "$skill"
    done
    printf '  mcp: []\n'
  } > "$out/user-apm.yml"
}

# Fails when a skill names another skill by name and does not declare it, or declares a name
# that is not a skill. Scans the built .md files of each skill.
check_references() {  # out
  local out="$1" skill ref refname target wrapper declared targets dep errs=0 pairs
  pairs="$WORK/pairs.tsv"
  : > "$pairs"
  for skill in $(list_skills); do
    printf '%s\t%s\n' "$skill" "$skill" >> "$pairs"
    ref="$(upstream_ref "$SKILLS_DIR/$skill/SKILL.md")"
    if [[ -n "$ref" ]]; then
      refname="${ref#*/}"
      if [[ "$refname" != "$skill" ]]; then
        printf '%s\t%s\n' "$refname" "$skill" >> "$pairs"
      fi
    fi
  done
  for wrapper in $(list_skills); do
    declared=" $(deps_for "$wrapper") "
    mentioned=" $(mentions_for "$wrapper") "
    for dep in $(deps_for "$wrapper") $(mentions_for "$wrapper"); do
      if [[ ! -d "$SKILLS_DIR/$dep" ]]; then
        printf 'error: %s declares %s, which is not a skill\n' "$wrapper" "$dep" >&2
        errs=1
      fi
    done
    targets=""
    while IFS=$'\t' read -r refname target; do
      if [[ "$target" == "$wrapper" ]]; then continue; fi
      case " $targets " in *" $target "*) continue ;; esac
      if grep -r --include='*.md' -E -q -e "$(name_pattern "$refname")" "$out/skills/$wrapper"; then
        targets="$targets $target"
      fi
    done < "$pairs"
    for target in $targets; do
      case "$declared$mentioned" in
        *" $target "*) ;;
        *)
          printf 'error: %s names %s, but %s does not list it. Add it as a dependency, or as a mention if it is not called: %s\n' \
            "$wrapper" "$target" "$DEPS_FILE" "$wrapper mentions: $target" >&2
          errs=1
          ;;
      esac
    done
  done
  if [[ "$errs" -ne 0 ]]; then
    die "fix $DEPS_FILE, then run task build-apm"
  fi
}

mode=build
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) usage ;;
esac

OUT="$WORK/out"
mkdir -p "$OUT/skills"
for skill in $(list_skills); do
  build_skill "$skill" "$OUT"
done
write_user_manifest "$OUT"
check_references "$OUT"

if [[ "$mode" == check ]]; then
  if ! diff -r "$DIST_DIR" "$OUT" > "$WORK/diff.txt" 2>&1; then
    head -n 40 "$WORK/diff.txt" >&2
    die "dist/ is out of date. Run task build-apm and commit the result."
  fi
  printf 'build-apm: dist/ is current\n'
else
  rm -rf "$DIST_DIR"
  cp -R "$OUT" "$DIST_DIR"
  printf 'built %s skills into dist/\n' "$(list_skills | wc -l | tr -d ' ')"
fi
