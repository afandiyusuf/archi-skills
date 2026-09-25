# Shared settings for the setup-worktree scripts. Sourced, not executed.

SLS_ROOT="${SLS_ROOT:-$HOME/Documents/Workspace/sls}"
STAGING_DIR="$SLS_ROOT/staging"
API_DIR="sentec-loyalty-system-api"
WEB_DIR="sentec-loyalty-system-web"
REPOS=("$API_DIR" "$WEB_DIR")
BASE_BRANCH="staging"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAKEFILE_TEMPLATE="$SKILL_DIR/templates/Makefile"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# Task folder names: lowercase letters, digits and dashes, e.g. sls-785-sls-797.
valid_task_name() { [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] && [[ "$1" != "staging" ]]; }
