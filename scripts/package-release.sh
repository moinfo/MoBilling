#!/usr/bin/env bash
# Build a distributable, turnkey MoBilling package for a self-hosted customer.
#
# Usage:  scripts/package-release.sh <version>   e.g. scripts/package-release.sh 1.0.0
#
# Produces mobilling-<version>.zip containing:
#   api/          Laravel backend, source + vendor/ pre-installed (--no-dev)
#   public_html/  pre-built frontend bundle (no Node/npm needed on the customer's server)
#   INSTALL.md, nginx.conf.example
#
# Source is exported via `git archive HEAD`, so anything gitignored (vendor,
# node_modules, .env, storage/logs, this repo's own local build artifacts)
# is never in the package to begin with — no separate exclude list to
# maintain. A short explicit list below removes docs that are internal to
# running MoBilling's *own* SaaS instance (WHMCS migration notes etc.) and
# have no place in a customer's copy.
set -euo pipefail

VERSION="${1:?Usage: scripts/package-release.sh <version>  e.g. scripts/package-release.sh 1.0.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${MOBILLING_RELEASE_OUT:-$ROOT/../mobilling-releases}"
PKG="mobilling-${VERSION}"
STAGE="$(mktemp -d)"
PKG_DIR="$STAGE/$PKG"

log() { echo -e "\033[0;32m[package]\033[0m $1"; }

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

log "Exporting tracked source from git HEAD…"
mkdir -p "$PKG_DIR"
git -C "$ROOT" archive HEAD unganisha-api mobilling-ui | tar -x -C "$PKG_DIR"
mv "$PKG_DIR/unganisha-api" "$PKG_DIR/api"

log "Removing docs internal to MoBilling's own SaaS instance…"
rm -f "$PKG_DIR/api/docs/IMPLEMENTATION_PLAN.md" \
      "$PKG_DIR/api/docs/WHMCS_PARALLEL_OPERATION.md"

log "Recreating empty runtime directories git doesn't track…"
mkdir -p "$PKG_DIR/api/storage/framework/sessions" \
         "$PKG_DIR/api/storage/framework/views" \
         "$PKG_DIR/api/storage/logs" \
         "$PKG_DIR/api/bootstrap/cache"

log "Installing backend dependencies (composer install --no-dev)…"
(cd "$PKG_DIR/api" && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --no-interaction --optimize-autoloader --prefer-dist -q)
find "$PKG_DIR/api/vendor" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

log "Preparing shipped .env (APP_VERSION=${VERSION}, production defaults)…"
cp "$PKG_DIR/api/.env.example" "$PKG_DIR/api/.env"
{
  echo ""
  echo "APP_VERSION=${VERSION}"
} >> "$PKG_DIR/api/.env"
sed -i \
  -e 's/^APP_NAME=.*/APP_NAME=MoBilling/' \
  -e 's/^APP_ENV=.*/APP_ENV=production/' \
  -e 's/^APP_DEBUG=.*/APP_DEBUG=false/' \
  -e 's/^DB_CONNECTION=.*/DB_CONNECTION=mysql/' \
  "$PKG_DIR/api/.env"
# The installer's first step checks .env is writable by whichever user
# PHP-FPM runs as — unknown at packaging time, so make it writable by
# everyone for setup and tell the customer to tighten it back down
# afterwards (INSTALL.md's last step), rather than leaving them stuck on
# an opaque "env not writable" failure if they run the wizard before (or
# instead of) following the ownership steps in INSTALL.md.
chmod 666 "$PKG_DIR/api/.env"

log "Building frontend (production bundle)…"
(cd "$PKG_DIR/mobilling-ui" && npm ci --silent && npm run build --silent)
mkdir -p "$PKG_DIR/public_html"
cp -r "$PKG_DIR/mobilling-ui/dist/." "$PKG_DIR/public_html/"
rm -rf "$PKG_DIR/mobilling-ui"

log "Adding install docs…"
cp "$ROOT/scripts/package-templates/INSTALL.md" "$PKG_DIR/INSTALL.md"
cp "$ROOT/scripts/package-templates/INSTALL-CPANEL.md" "$PKG_DIR/INSTALL-CPANEL.md"
cp "$ROOT/scripts/package-templates/nginx.conf.example" "$PKG_DIR/nginx.conf.example"

mkdir -p "$OUT_DIR"
ZIP_PATH="$OUT_DIR/${PKG}.zip"
rm -f "$ZIP_PATH"
log "Zipping to $ZIP_PATH…"
(cd "$STAGE" && zip -qr "$ZIP_PATH" "$PKG")

log "Done: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"
