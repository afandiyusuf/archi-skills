#!/usr/bin/env bash
# One-time setup of ~/Documents/Workspace/sls/staging/.
# Clones both repos on the staging branch, copies the ignored secret files
# from existing checkouts, installs dependencies and adds the Makefile.
#
# Usage: bootstrap.sh [--api-src <dir>] [--web-src <dir>]
set -euo pipefail
source "$(dirname "$0")/common.sh"

API_SRC="$HOME/Documents/Workspace/sentec-loyalty-system-api"
WEB_SRC="$HOME/Documents/Workspace/sentec-loyalty-system-web"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-src) API_SRC="$2"; shift 2 ;;
    --web-src) WEB_SRC="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -e "$STAGING_DIR" ]] && die "$STAGING_DIR already exists; refusing to overwrite it."
[[ -d "$API_SRC/.git" || -f "$API_SRC/.git" ]] || die "API source checkout not found: $API_SRC"
[[ -d "$WEB_SRC/.git" || -f "$WEB_SRC/.git" ]] || die "Web source checkout not found: $WEB_SRC"

mkdir -p "$STAGING_DIR"

for pair in "$API_DIR:$API_SRC" "$WEB_DIR:$WEB_SRC"; do
  name="${pair%%:*}"; src="${pair#*:}"
  url="$(git -C "$src" remote get-url origin)"
  info "Cloning $url ($BASE_BRANCH) into staging/$name"
  git clone --branch "$BASE_BRANCH" "$url" "$STAGING_DIR/$name"
done

# Ignored files to carry over. Only the live ones; *.bak files stay behind.
info "Copying API secrets from $API_SRC"
for f in config.json scripts/config.json docs/bruno/membership-sentec-bruno/environments/local.secrets.bru; do
  if [[ -f "$API_SRC/$f" ]]; then
    mkdir -p "$STAGING_DIR/$API_DIR/$(dirname "$f")"
    cp -a "$API_SRC/$f" "$STAGING_DIR/$API_DIR/$f"
    echo "  $f"
  else
    echo "  (missing, skipped) $f"
  fi
done

info "Copying web .env from $WEB_SRC (API URL set to local)"
if [[ -f "$WEB_SRC/.env" ]]; then
  sed -E 's#^VITE_API_BASE_URL=.*#VITE_API_BASE_URL=http://localhost:8081#' "$WEB_SRC/.env" \
    | grep -v '^# Local run against STAGING' > "$STAGING_DIR/$WEB_DIR/.env"
else
  echo "  (missing) .env - create it in staging/$WEB_DIR before running the CMS"
fi

# Dependencies. vendor/ holds private modules, so fall back to copying it.
info "Vendoring Go modules"
if ! (cd "$STAGING_DIR/$API_DIR" && go mod vendor); then
  echo "  go mod vendor failed; copying vendor/ from $API_SRC instead"
  cp -a "$API_SRC/vendor" "$STAGING_DIR/$API_DIR/vendor"
fi

info "Installing web dependencies (npm ci)"
(cd "$STAGING_DIR/$WEB_DIR" && npm ci)

cp "$MAKEFILE_TEMPLATE" "$STAGING_DIR/Makefile"

for r in "${REPOS[@]}"; do
  if [[ -n "$(git -C "$STAGING_DIR/$r" status --porcelain)" ]]; then
    echo "WARNING: staging/$r has tracked changes after install:"
    git -C "$STAGING_DIR/$r" status --short
  fi
done

info "Done: $STAGING_DIR"
