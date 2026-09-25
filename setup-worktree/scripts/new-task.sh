#!/usr/bin/env bash
# Create a task folder by copying staging/ and branching each repo.
#
# Usage: new-task.sh <task-name> [--api <branch>] [--web <branch>] [--web-api local|staging]
#   A repo without a branch stays on staging (it is still copied, untouched).
#
# Example: new-task.sh sls-785-sls-797 \
#            --api feature/SLS-785-mobile-app-build-files \
#            --web feature/SLS-797-mobile-app-branding-cms
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ $# -ge 1 ]] || die "usage: new-task.sh <task-name> [--api <branch>] [--web <branch>] [--web-api local|staging]"
TASK="$1"; shift
API_BRANCH=""; WEB_BRANCH=""; WEB_API="local"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api) API_BRANCH="$2"; shift 2 ;;
    --web) WEB_BRANCH="$2"; shift 2 ;;
    --web-api) WEB_API="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

valid_task_name "$TASK" || die "bad task name '$TASK' (use lowercase like sls-785-sls-797)"
[[ -n "$API_BRANCH$WEB_BRANCH" ]] || die "give at least one of --api / --web"
[[ "$WEB_API" == "local" || "$WEB_API" == "staging" ]] || die "--web-api must be local or staging"
[[ -d "$STAGING_DIR" ]] || die "$STAGING_DIR missing; run bootstrap.sh first"

TARGET="$SLS_ROOT/$TASK"
[[ -e "$TARGET" ]] && die "$TARGET already exists"

for b in "$API_BRANCH" "$WEB_BRANCH"; do
  [[ -z "$b" ]] || git check-ref-format --branch "$b" >/dev/null || die "invalid branch name: $b"
done

# 1. Refresh staging/ so the copy starts from the latest origin/staging.
for r in "${REPOS[@]}"; do
  repo="$STAGING_DIR/$r"
  cur="$(git -C "$repo" branch --show-current)"
  [[ "$cur" == "$BASE_BRANCH" ]] || die "staging/$r is on '$cur', expected '$BASE_BRANCH'"
  if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    git -C "$repo" status --short
    die "staging/$r has uncommitted tracked changes; clean it first"
  fi
  before="$(git -C "$repo" rev-parse HEAD)"
  info "Pulling origin/$BASE_BRANCH in staging/$r"
  git -C "$repo" pull --ff-only origin "$BASE_BRANCH"
  after="$(git -C "$repo" rev-parse HEAD)"

  if [[ "$before" != "$after" ]]; then
    if [[ "$r" == "$API_DIR" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- go.mod go.sum; then
      info "go.mod changed; re-vendoring staging/$r"
      (cd "$repo" && go mod vendor)
    fi
    if [[ "$r" == "$WEB_DIR" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- package.json package-lock.json; then
      info "package files changed; running npm ci in staging/$r"
      (cd "$repo" && npm ci)
    fi
  fi
done

# 2. Copy everything, including secrets, vendor/ and node_modules/.
info "Copying staging/ to $TASK/"
cp -a "$STAGING_DIR" "$TARGET"
cp "$MAKEFILE_TEMPLATE" "$TARGET/Makefile"
rm -f "$TARGET/local.mk"
if [[ "$WEB_API" == "staging" ]]; then
  echo "API := staging" > "$TARGET/local.mk"
fi

# 3. Branch the repos that belong to this task.
branch_repo() {
  local r="$1" b="$2"
  [[ -n "$b" ]] || return 0
  git -C "$TARGET/$r" checkout -b "$b"
}
branch_repo "$API_DIR" "$API_BRANCH"
branch_repo "$WEB_DIR" "$WEB_BRANCH"

info "Ready: $TARGET"
printf "  api: %s\n" "$(git -C "$TARGET/$API_DIR" branch --show-current)"
printf "  web: %s\n" "$(git -C "$TARGET/$WEB_DIR" branch --show-current)"
printf "  CMS -> %s API\n" "$WEB_API"
