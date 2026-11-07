#!/usr/bin/env bash
# Copies upstream skills into plugins/alf/upstream, records each upstream skill's commit in PIN.md,
# and writes the wrapper skills under plugins/alf/skills. Then rebuilds dist/ with build-apm.sh.
# Run by `task update-upstream`, by the weekly workflow, and by agents. See AGENTS.md.
#
# Written for bash 3.2 (macOS /bin/bash): plain variables, loops and case only.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$REPO_DIR/plugins/alf"
UPSTREAM_DIR="$PLUGIN_DIR/upstream"
SKILLS_DIR="$PLUGIN_DIR/skills"
OVERLAY_START='<!-- overlay:start -->'
OVERLAY_END='<!-- overlay:end -->'
REVIEW_NOTE='Reviewer: check LICENSE changes, and check for missing upstream skills if an updated upstream skill links other skills. See AGENTS.md.'

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/rows" "$WORK_DIR/clones"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/update-upstream.sh update [--dry-run] [--ref REV] [SKILL]
      Move unpinned upstream skills to the latest revision of their upstream folder.
      With SKILL, move that one upstream skill to latest. With SKILL and --ref REV, pin it to REV.
  scripts/update-upstream.sh add UPSTREAM URL PATH[=WRAPPER]...
      Copy upstream skills from an upstream into the catalogue. Writes the files; commit them yourself.
      WRAPPER is the name of the plugin skill that points at the upstream skill (default: the folder name).

Environment for update:
  UPSTREAM_BRANCH        branch for the update (default: upstream/update-<UTC timestamp>)
  UPSTREAM_LOCAL_ONLY=1  commit to the branch, but skip the push and the PR
EOF
  exit 2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Upstream URL from the PIN.md line "Upstream: <url>".
pin_url() {
  awk -F': ' '$1 == "Upstream" { print $2; exit }' "$1"
}

# Table rows of a PIN.md, printed as: skill upstream-path commit pinned wrapper
pin_rows() {
  awk -F'|' '
    /^\| / && $2 !~ /^ *Skill *$/ && $2 !~ /^ *-+ *$/ {
      for (i = 2; i <= 6; i++) gsub(/^ +| +$/, "", $i)
      print $2, $3, $4, $5, $6
    }' "$1"
}

load_rows() {   # slug
  pin_rows "$UPSTREAM_DIR/$1/PIN.md" > "$WORK_DIR/rows/$1"
}

# Sets commit and pinned for one upstream skill in an upstream's rows file.
set_row() {   # slug skill commit pinned
  local rows="$WORK_DIR/rows/$1" tmp="$WORK_DIR/rows.tmp"
  awk -v s="$2" -v c="$3" -v p="$4" '$1 == s { $3 = c; $4 = p } { print }' "$rows" > "$tmp"
  mv "$tmp" "$rows"
}

# Rewrites PIN.md for one upstream from its rows file.
write_pin() {   # slug url rows-file
  {
    printf 'Upstream: %s\n\n' "$2"
    printf 'Files under this folder are copied from the commits in the table by scripts/update-upstream.sh.\n'
    printf 'Edit only through scripts/update-upstream.sh. Rows marked yes are skipped by the weekly update.\n\n'
    printf '| Skill | Upstream path | Commit | Pinned | Wrapper |\n'
    printf '| --- | --- | --- | --- | --- |\n'
    awk '{ printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5 }' "$3"
  } > "$UPSTREAM_DIR/$1/PIN.md"
}

# Clones an upstream once per run. Prints the clone directory.
clone_upstream() {   # slug url
  local dir="$WORK_DIR/clones/$1"
  if [[ ! -d "$dir" ]]; then
    git clone --quiet "$2" "$dir" || die "cannot clone $2"
  fi
  printf '%s\n' "$dir"
}

default_head() {   # clone
  git -C "$1" rev-parse --verify --quiet 'origin/HEAD^{commit}' || die "no default branch in $1"
}

# Newest commit on the default branch that changes a folder.
latest_commit() {   # clone upstream-path
  git -C "$1" log -1 --format=%H "$(default_head "$1")" -- "$2"
}

# Newest commit at a revision that changes a folder.
commit_at() {   # clone rev upstream-path
  local rev
  rev="$(git -C "$1" rev-parse --verify --quiet "$2^{commit}")" || die "unknown revision: $2"
  git -C "$1" log -1 --format=%H "$rev" -- "$3"
}

# Copies a folder as it was at a commit to dest, replacing whatever is there.
export_folder() {   # clone commit upstream-path dest
  local tmp
  tmp="$(mktemp -d "$WORK_DIR/export.XXXXXX")"
  git -C "$1" archive "$2" -- "$3" | tar -x -C "$tmp"
  rm -rf "$4"
  mkdir -p "$(dirname "$4")"
  mv "$tmp/$3" "$4"
}

# The name: value of a SKILL.md frontmatter block.
skill_name() {   # SKILL.md
  awk 'NR > 1 && /^---$/ { exit } /^name:/ { sub(/^name: */, ""); print; exit }' "$1"
}

# The frontmatter block of a SKILL.md, from its first line through the closing ---.
frontmatter() {   # SKILL.md
  awk '{ print } NR > 1 && /^---$/ { exit }' "$1"
}

# Succeeds if a name is already used by an upstream skill (folder name) or a wrapper (skill name).
skill_in_catalogue() {   # name
  local pin
  if [[ -e "$SKILLS_DIR/$1" ]]; then
    return 0
  fi
  for pin in "$UPSTREAM_DIR"/*/PIN.md; do
    [[ -f "$pin" ]] || continue
    if pin_rows "$pin" | awk -v s="$1" '$1 == s || $5 == s { found = 1 } END { exit !found }'; then
      return 0
    fi
  done
  return 1
}

# The wrapper name of an upstream skill, from its upstream's rows file.
wrapper_for() {   # slug skill
  awk -v s="$2" '$1 == s { print $5; exit }' "$WORK_DIR/rows/$1"
}

# Writes the wrapper for an upstream skill under its wrapper name. Frontmatter and pointer are
# regenerated (the name line is replaced when the wrapper name differs); the overlay is kept.
write_wrapper() {   # slug skill wrapper-name
  local upstream_skill="$UPSTREAM_DIR/$1/$2/SKILL.md"
  local dir="$SKILLS_DIR/$3"
  local wrapper="$dir/SKILL.md"
  local overlay
  [[ -n "$3" ]] || die "no wrapper name for $1/$2"
  [[ "$(head -n 1 "$upstream_skill")" == "---" ]] || die "$upstream_skill has no frontmatter"
  [[ "$(skill_name "$upstream_skill")" == "$2" ]] || die "$upstream_skill: frontmatter name does not match folder $2"
  if [[ -f "$wrapper" ]]; then
    overlay="$(awk -v s="$OVERLAY_START" -v e="$OVERLAY_END" '$0 == s { on = 1 } on { print } $0 == e { exit }' "$wrapper")"
    [[ "$overlay" == *"$OVERLAY_END" ]] || die "$wrapper: overlay markers are missing; fix this file by hand"
  else
    overlay="$OVERLAY_START
$OVERLAY_END"
  fi
  mkdir -p "$dir"
  {
    if [[ "$3" == "$2" ]]; then
      frontmatter "$upstream_skill"
    else
      frontmatter "$upstream_skill" | awk -v n="$3" '/^name:/ && !done { print "name: " n; done = 1; next } { print }'
    fi
    printf '\nFollow the skill in full at `../../upstream/%s/%s/SKILL.md`. Read it first and do what it says, using the reference files beside it.\n\n' "$1" "$2"
    printf '<!-- Local additions go between the markers. scripts/update-upstream.sh rewrites everything else. -->\n'
    printf '%s\n' "$overlay"
  } > "$wrapper"
}

# Writes the default-branch LICENSE of an upstream to WORK_DIR/license.<slug>, if it has one.
fresh_license() {   # slug
  local clone="$WORK_DIR/clones/$1" head
  head="$(default_head "$clone")"
  if git -C "$clone" cat-file -e "$head:LICENSE" 2>/dev/null; then
    git -C "$clone" show "$head:LICENSE" > "$WORK_DIR/license.$1"
    return 0
  fi
  return 1
}

# Records an upstream whose LICENSE differs from the copy on disk.
check_license() {   # slug
  if ! fresh_license "$1"; then
    printf 'warning: %s has no LICENSE on its default branch; kept the existing copy\n' "$1" >&2
  elif ! cmp -s "$WORK_DIR/license.$1" "$UPSTREAM_DIR/$1/LICENSE"; then
    printf '%s\n' "$1" >> "$WORK_DIR/license_changes"
  fi
}

# Dies on broken overlay markers in an existing wrapper. Runs during planning.
check_overlay() {   # wrapper-name
  local wrapper="$SKILLS_DIR/$1/SKILL.md" overlay
  [[ -f "$wrapper" ]] || return 0
  overlay="$(awk -v s="$OVERLAY_START" -v e="$OVERLAY_END" '$0 == s { on = 1 } on { print } $0 == e { exit }' "$wrapper")"
  [[ "$overlay" == *"$OVERLAY_END" ]] || die "$wrapper: overlay markers are missing; fix this file by hand"
}

# Exports a changed upstream skill to a staging folder and checks it.
stage_upstream() {   # clone commit upstream-path slug skill wrapper-name
  local stage="$WORK_DIR/stage/$4/$5"
  export_folder "$1" "$2" "$3" "$stage"
  [[ "$(head -n 1 "$stage/SKILL.md")" == "---" ]] || die "$4/$5: new revision has no frontmatter"
  [[ "$(skill_name "$stage/SKILL.md")" == "$5" ]] || die "$4/$5: new revision's frontmatter name does not match"
  check_overlay "$6"
}

# Skills next to a copied one that are new since the old commit and not in the catalogue.
new_upstream_skills() {   # slug parent-path old new
  local clone="$WORK_DIR/clones/$1" name
  git -C "$clone" ls-tree -d --name-only "$4:$2" 2>/dev/null | while read -r name; do
    if git -C "$clone" cat-file -e "$4:$2/$name/SKILL.md" 2>/dev/null \
      && ! git -C "$clone" cat-file -e "$3:$2/$name/SKILL.md" 2>/dev/null \
      && ! skill_in_catalogue "$name"; then
      printf -- '- %s/%s\n' "$2" "$name"
    fi
  done
}

# Writes the PR body for a plan file (slug skill upath old new pinned).
write_body() {   # plan-file body-file
  local slug skill upath old new pinned_new url found
  {
    printf 'Moves upstream skills to the revisions below. Generated by scripts/update-upstream.sh.\n\n'
    printf '| Upstream skill | From | To | Pinned |\n| --- | --- | --- | --- |\n'
    while read -r slug skill upath old new pinned_new; do
      printf '| %s/%s | %s | %s | %s |\n' "$slug" "$skill" "${old:0:7}" "${new:0:7}" "$pinned_new"
    done < "$1"
    printf '\nCompare upstream:\n\n'
    while read -r slug skill upath old new pinned_new; do
      if [[ "$old" != "$new" ]]; then
        url="$(pin_url "$UPSTREAM_DIR/$slug/PIN.md")"
        printf -- '- %s/%s: %s/compare/%s...%s\n' "$slug" "$skill" "$url" "$old" "$new"
      fi
    done < "$1"
    printf '\nCommits that touch the copied skills:\n\n'
    while read -r slug skill upath old new pinned_new; do
      if [[ "$old" != "$new" ]]; then
        printf '%s/%s:\n' "$slug" "$skill"
        if [[ -n "$(git -C "$WORK_DIR/clones/$slug" log -n 1 --format=%h "$old..$new" -- "$upath")" ]]; then
          git -C "$WORK_DIR/clones/$slug" log -n 20 --format='- %h %s' "$old..$new" -- "$upath"
        else
          printf '(moved to an earlier revision; commits dropped by this change:)\n'
          git -C "$WORK_DIR/clones/$slug" log -n 20 --format='- %h %s' "$new..$old" -- "$upath"
        fi
      fi
    done < "$1"
    printf '\nNew upstream skills next to the copied ones, not copied:\n\n'
    found="$(while read -r slug skill upath old new pinned_new; do
      if [[ "$old" != "$new" ]]; then
        new_upstream_skills "$slug" "$(dirname "$upath")" "$old" "$new"
      fi
    done < "$1" | sort -u)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
    else
      printf 'None.\n'
    fi
    if [[ -s "$WORK_DIR/license_changes" ]]; then
      printf '\nLICENSE changed upstream for:\n\n'
      sed 's/^/- /' "$WORK_DIR/license_changes"
    fi
    printf '\n%s\n' "$REVIEW_NOTE"
  } > "$2"
}

cmd_add() {
  [[ $# -ge 3 ]] || usage
  local slug="$1" url="$2" folder clone head path skill commit
  shift 2
  folder="$UPSTREAM_DIR/$slug"
  clone="$(clone_upstream "$slug" "$url")"
  head="$(default_head "$clone")"
  if [[ -f "$folder/PIN.md" ]]; then
    [[ "$(pin_url "$folder/PIN.md")" == "$url" ]] || die "$folder/PIN.md is for a different upstream"
    load_rows "$slug"
  else
    mkdir -p "$folder"
    git -C "$clone" cat-file -e "$head:LICENSE" 2>/dev/null || die "$url has no LICENSE on its default branch"
    git -C "$clone" show "$head:LICENSE" > "$folder/LICENSE"
    : > "$WORK_DIR/rows/$slug"
  fi
  for arg in "$@"; do
    path="${arg%%=*}"
    path="${path%/}"
    skill="${path##*/}"
    wname="$skill"
    if [[ "$arg" == *=* ]]; then
      wname="${arg#*=}"
    fi
    [[ -n "$wname" && "$wname" != */* ]] || die "bad wrapper name in $arg"
    git -C "$clone" cat-file -e "$head:$path/SKILL.md" 2>/dev/null || die "$path/SKILL.md not found on $url"
    if skill_in_catalogue "$skill"; then
      die "$skill is already in the catalogue"
    fi
    if skill_in_catalogue "$wname"; then
      die "wrapper name $wname is already in the catalogue"
    fi
    commit="$(git -C "$clone" log -1 --format=%H "$head" -- "$path")"
    [[ -n "$commit" ]] || die "$path has no commits on $url"
    export_folder "$clone" "$commit" "$path" "$folder/$skill"
    [[ "$(skill_name "$folder/$skill/SKILL.md")" == "$skill" ]] || die "$path: frontmatter name does not match its folder"
    write_wrapper "$slug" "$skill" "$wname"
    printf '%s %s %s %s %s\n' "$skill" "$path" "$commit" no "$wname" >> "$WORK_DIR/rows/$slug"
    printf 'added %s/%s at %s as wrapper %s\n' "$slug" "$skill" "${commit:0:7}" "$wname"
  done
  write_pin "$slug" "$url" "$WORK_DIR/rows/$slug"
  printf 'Done. Review with git status, then commit.\n'
}

cmd_update() {
  local dry_run=0 ref="" only="" matched=0
  local pin slug url skill upath old pinned new pinned_new clone plan body title count branch
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      --ref)
        [[ $# -ge 2 ]] || usage
        ref="$2"
        shift
        ;;
      -*) usage ;;
      *)
        [[ -z "$only" ]] || usage
        only="$1"
        ;;
    esac
    shift
  done
  [[ -z "$ref" || -n "$only" ]] || die "--ref needs a single SKILL"

  if [[ "$dry_run" -eq 0 ]]; then
    [[ "$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)" == main ]] || die "run from main"
    [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]] || die "working tree has local changes; commit or stash them first"
  fi

  # Plan: which rows move, and which LICENSE files differ.
  # Each changed upstream skill is exported to a staging folder and checked before any file is replaced.
  plan="$WORK_DIR/plan"
  : > "$plan"
  rm -f "$WORK_DIR/license_changes"
  for pin in "$UPSTREAM_DIR"/*/PIN.md; do
    [[ -f "$pin" ]] || continue
    slug="$(basename "$(dirname "$pin")")"
    url="$(pin_url "$pin")"
    [[ -n "$url" ]] || die "$pin has no Upstream line"
    load_rows "$slug"
    clone="$(clone_upstream "$slug" "$url")"
    check_license "$slug"
    while read -r skill upath old pinned _wrapper; do
      [[ -n "$skill" ]] || continue
      if [[ -n "$only" && "$skill" != "$only" ]]; then continue; fi
      if [[ -z "$only" && "$pinned" == yes ]]; then continue; fi
      matched=1
      if [[ -n "$ref" ]]; then
        new="$(commit_at "$clone" "$ref" "$upath")"
        pinned_new=yes
      else
        new="$(latest_commit "$clone" "$upath")"
        pinned_new=no
      fi
      [[ -n "$new" ]] || die "$upath not found on $url"
      if [[ "$new" != "$old" || "$pinned_new" != "$pinned" ]]; then
        printf '%s %s %s %s %s %s\n' "$slug" "$skill" "$upath" "$old" "$new" "$pinned_new" >> "$plan"
      fi
      if [[ "$new" != "$old" ]]; then
        stage_upstream "$clone" "$new" "$upath" "$slug" "$skill" "$(wrapper_for "$slug" "$skill")"
      fi
    done < "$WORK_DIR/rows/$slug"
  done
  [[ "$matched" -eq 1 || -z "$only" ]] || die "no upstream skill named $only"

  if [[ ! -s "$plan" && ! -s "$WORK_DIR/license_changes" ]]; then
    printf 'All selected upstream skills are current.\n'
    exit 0
  fi
  if [[ -s "$plan" ]]; then
    printf 'Planned changes:\n'
    while read -r slug skill upath old new pinned_new; do
      printf '  %s/%s  %s -> %s  pinned: %s\n' "$slug" "$skill" "${old:0:7}" "${new:0:7}" "$pinned_new"
    done < "$plan"
  fi
  if [[ -s "$WORK_DIR/license_changes" ]]; then
    printf 'LICENSE changed upstream, copy will be refreshed: %s\n' "$(tr '\n' ' ' < "$WORK_DIR/license_changes")"
  fi
  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Dry run: printed the plan.\n'
    exit 0
  fi

  # Apply: move staged upstream skills into place, then wrappers, LICENSE files and pins.
  while read -r slug skill upath old new pinned_new; do
    if [[ "$old" != "$new" ]]; then
      rm -rf "$UPSTREAM_DIR/$slug/$skill"
      mv "$WORK_DIR/stage/$slug/$skill" "$UPSTREAM_DIR/$slug/$skill"
      write_wrapper "$slug" "$skill" "$(wrapper_for "$slug" "$skill")"
    fi
    set_row "$slug" "$skill" "$new" "$pinned_new"
  done < "$plan"
  if [[ -s "$WORK_DIR/license_changes" ]]; then
    while read -r slug; do
      cp "$WORK_DIR/license.$slug" "$UPSTREAM_DIR/$slug/LICENSE"
    done < "$WORK_DIR/license_changes"
  fi
  while read -r slug; do
    write_pin "$slug" "$(pin_url "$UPSTREAM_DIR/$slug/PIN.md")" "$WORK_DIR/rows/$slug"
  done < <(cut -d' ' -f1 "$plan" | sort -u)

  # Rebuild the APM bundles from the changed copies. A failing build stops the update here.
  "$REPO_DIR/scripts/build-apm.sh"

  if [[ -z "$(git -C "$REPO_DIR" status --porcelain -- plugins/alf dist)" ]]; then
    printf 'Files already match; skipped the commit.\n'
    exit 0
  fi

  if [[ ! -s "$plan" ]]; then
    title="Refresh LICENSE for $(tr '\n' ' ' < "$WORK_DIR/license_changes")"
  elif [[ -n "$ref" ]]; then
    title="Pin $only to $ref"
  elif [[ -n "$only" ]]; then
    title="Update $only to latest"
  else
    count="$(wc -l < "$plan" | tr -d ' ')"
    title="Update $count upstream skill(s) to latest"
  fi
  body="$WORK_DIR/body.md"
  write_body "$plan" "$body"
  {
    printf '%s\n\n' "$title"
    cat "$body"
  } > "$WORK_DIR/commit.txt"

  branch="${UPSTREAM_BRANCH:-upstream/update-$(date -u +%Y%m%d-%H%M%S)}"
  git -C "$REPO_DIR" checkout --quiet -B "$branch"
  git -C "$REPO_DIR" add -A -- plugins/alf dist
  git -C "$REPO_DIR" commit --quiet -F "$WORK_DIR/commit.txt"
  git -C "$REPO_DIR" checkout --quiet main
  if [[ "${UPSTREAM_LOCAL_ONLY:-0}" == 1 ]]; then
    printf 'Committed to %s and switched back to main. Push and PR skipped (UPSTREAM_LOCAL_ONLY=1).\n' "$branch"
    exit 0
  fi
  git -C "$REPO_DIR" push --quiet --force -u origin "$branch"
  if [[ "$(gh pr list --head "$branch" --state open --json number --jq length)" -gt 0 ]]; then
    printf 'An open PR already exists for %s; the push updated it.\n' "$branch"
  else
    gh pr create --base main --head "$branch" --title "$title" --body-file "$body"
  fi
}

case "${1:-}" in
  update) shift; cmd_update "$@" ;;
  add) shift; cmd_add "$@" ;;
  *) usage ;;
esac
