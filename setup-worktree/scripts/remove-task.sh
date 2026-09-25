#!/usr/bin/env bash
# Check, then delete, a task folder.
#
# Usage: remove-task.sh <task-name>          # report only, deletes nothing
#        remove-task.sh <task-name> --yes    # delete if nothing would be lost
#
# Blocks deletion when a repo has uncommitted changes or commits that are
# not on GitHub, or when the folder is still running the API / CMS.
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ $# -ge 1 ]] || die "usage: remove-task.sh <task-name> [--yes]"
TASK="$1"; CONFIRM="${2:-}"
valid_task_name "$TASK" || die "bad task name '$TASK' (staging/ can never be removed)"
TARGET="$SLS_ROOT/$TASK"
[[ -d "$TARGET" ]] || die "$TARGET does not exist"

blockers=0
echo "Task folder: $TARGET ($(du -sh "$TARGET" | cut -f1))"

for r in "${REPOS[@]}"; do
  repo="$TARGET/$r"
  [[ -d "$repo" ]] || { echo "  $r: missing"; continue; }
  git -C "$repo" fetch --quiet origin || echo "  $r: fetch failed, using cached remote refs"
  b="$(git -C "$repo" branch --show-current)"
  echo "  $r: branch $b"

  dirty="$(git -C "$repo" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    echo "    BLOCK: uncommitted changes:"
    echo "$dirty" | sed 's/^/      /'
    blockers=1
  fi

  # Commits that exist only here: not on origin/<branch> and not on origin/staging.
  refs=("origin/$BASE_BRANCH")
  git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$b" >/dev/null && refs+=("origin/$b")
  local_only="$(git -C "$repo" log --oneline HEAD --not "${refs[@]}")"
  # A squash-merged PR whose remote branch was deleted: the commits live in the PR.
  if [[ -n "$local_only" && "$b" != "$BASE_BRANCH" ]] && command -v gh >/dev/null; then
    head="$(git -C "$repo" rev-parse HEAD)"
    merged="$(cd "$repo" && gh pr list --head "$b" --state merged --json number,headRefOid \
      --jq ".[] | select(.headRefOid == \"$head\") | .number" 2>/dev/null | head -n1 || true)"
    if [[ -n "$merged" ]]; then
      echo "    ok: HEAD was merged in PR #$merged"
      local_only=""
      merged_ok=1
    fi
  fi
  if [[ -n "$local_only" ]]; then
    echo "    BLOCK: commits not pushed to GitHub:"
    echo "$local_only" | sed 's/^/      /'
    blockers=1
  elif [[ -z "${merged_ok:-}" ]]; then
    echo "    ok: every commit is on GitHub"
  fi
  unset merged_ok
done

api_owner="$(docker ps --filter "publish=8081" --format '{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null | head -n1 || true)"
if [[ "$api_owner" == "$TARGET/$API_DIR" ]]; then
  echo "  BLOCK: this folder's API is running (make down first)"
  blockers=1
fi
web_pid="$(ss -ltnpH 'sport = :5173' 2>/dev/null | grep -o 'pid=[0-9]*' | head -n1 | cut -d= -f2 || true)"
if [[ -n "$web_pid" && "$(readlink "/proc/$web_pid/cwd" 2>/dev/null)" == "$TARGET/"* ]]; then
  echo "  BLOCK: this folder's CMS dev server is running (Ctrl+C it first)"
  blockers=1
fi

if [[ "$blockers" -ne 0 ]]; then
  echo "Not safe to delete. Nothing was removed."
  exit 2
fi

if [[ "$CONFIRM" != "--yes" ]]; then
  echo "Safe to delete. Re-run with --yes to remove $TARGET."
  exit 0
fi

# Stopped containers still hold the compose project name; clear them.
docker compose -p "sls-$TASK" down --remove-orphans >/dev/null 2>&1 || true
rm -rf -- "$TARGET"
info "Removed $TARGET"
