#!/usr/bin/env bash
#
# deploy.sh — build the static site and rsync it to seed1's nginx root.
#
#   bash scripts/deploy.sh
#
# Default target is seed1.intelnav.net:/var/www/intelnav. Override with:
#   DEPLOY_HOST=seed2.intelnav.net DEPLOY_PATH=/var/www/intelnav bash scripts/deploy.sh
#
# Requires `next build` to have produced `out/`. We rebuild every run
# so deploy.sh is idempotent and you don't accidentally ship a stale
# build.

set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_HOST="${DEPLOY_HOST:-seed1.intelnav.net}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/intelnav}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/intelnav_seed1}"

cd "$(dirname "$0")/.."

echo "==> npm install (idempotent)"
npm install --silent

echo "==> next build (static export → out/)"
npx next build

if [ ! -d out ]; then
    echo "deploy: out/ wasn't produced — check next.config.mjs sets output:'export'" >&2
    exit 1
fi

echo "==> rsync out/ -> ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}"
# --delete-after: keep the live site whole until the new tree is in
# place. -t preserves mtimes so nginx etag-cache stays useful.
rsync -avzt --delete-after \
    -e "ssh -i ${SSH_KEY}" \
    out/ \
    "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/"

echo "==> verify https://intelnav.net"
curl -sSI -o /dev/null -w "  HTTP %{http_code}\n" https://intelnav.net/ || true

echo "✓ deployed"
