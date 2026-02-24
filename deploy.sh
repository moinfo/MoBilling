#!/bin/bash
#
# MoBilling Auto-Deploy Script
# Runs automatically after git pull (via post-merge hook)
# Can also be run manually: ./deploy.sh
#

set -e

PROJECT_DIR="/var/www/html/MoBilling"
API_DIR="$PROJECT_DIR/unganisha-api"
UI_DIR="$PROJECT_DIR/mobilling-ui"
NODE_BIN="$HOME/.nvm/versions/node/v20.19.3/bin"
LOG_FILE="$PROJECT_DIR/deploy.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[DEPLOY]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

# Detect what changed
detect_changes() {
    local changes
    changes=$(git -C "$PROJECT_DIR" diff --name-only HEAD@{1} HEAD 2>/dev/null || echo "all")

    API_CHANGED=false
    UI_CHANGED=false

    if [ "$changes" = "all" ]; then
        API_CHANGED=true
        UI_CHANGED=true
    else
        echo "$changes" | grep -q "^unganisha-api/" && API_CHANGED=true
        echo "$changes" | grep -q "^mobilling-ui/" && UI_CHANGED=true
    fi
}

deploy_api() {
    log "Deploying Laravel API..."

    cd "$API_DIR"

    # Install dependencies (no dev, optimized)
    log "Installing composer dependencies..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --no-interaction --optimize-autoloader --prefer-dist 2>&1

    # Clean .git dirs from vendor to save space
    find "$API_DIR/vendor" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

    # Run migrations
    log "Running database migrations..."
    php artisan migrate --force 2>&1

    # Clear and rebuild caches
    log "Caching config, routes, views..."
    php artisan config:cache 2>&1
    php artisan route:cache 2>&1
    php artisan view:cache 2>&1

    # Ensure storage link exists
    php artisan storage:link 2>&1 || true

    # Fix permissions
    chown -R www-data:www-data "$API_DIR/storage" "$API_DIR/bootstrap/cache"
    chmod -R 775 "$API_DIR/storage" "$API_DIR/bootstrap/cache"

    log "API deployment complete."
}

deploy_ui() {
    log "Deploying React Frontend..."

    cd "$UI_DIR"

    # Use Node 20
    export PATH="$NODE_BIN:$PATH"

    # Install dependencies
    log "Installing npm dependencies..."
    npm ci --silent 2>&1

    # Build for production
    log "Building frontend..."
    npm run build 2>&1

    log "Frontend deployment complete."
}

# ── Main ─────────────────────────────────────────────────────────────

echo ""
log "========== MoBilling Deploy Started =========="

detect_changes

if [ "$API_CHANGED" = true ]; then
    deploy_api
else
    log "No API changes detected, skipping backend deploy."
fi

if [ "$UI_CHANGED" = true ]; then
    deploy_ui
else
    log "No UI changes detected, skipping frontend deploy."
fi

# Reload Nginx (in case config changed)
nginx -t 2>&1 && systemctl reload nginx 2>&1
log "Nginx reloaded."

log "========== MoBilling Deploy Complete =========="
echo ""
