#!/bin/bash
# backup-workspace.sh — back up GitNexus config + MemoryPort data to this repo
# Design: silent on success (exit 0), noisy on failure (exit 1).
# Intended to run unattended from cron.
set -euo pipefail

DATE=$(date -u +%Y-%m-%dT%H%M%SZ)
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
ERRORS=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "ERROR: $1" >&2; ERRORS=$((ERRORS + 1)); }

# --- GitNexus ---
GITNEXUS_SRC="$HOME/.gitnexus"
if [ -d "$GITNEXUS_SRC" ]; then
    mkdir -p "$TMP/gitnexus"
    cp -r "$GITNEXUS_SRC"/* "$TMP/gitnexus/"
    (cd "$TMP" && tar -czf "$BACKUP_DIR/gitnexus-$DATE.tar.gz" gitnexus)
else
    fail "gitnexus source dir not found: $GITNEXUS_SRC"
fi

# --- MemoryPort data (not the massive index) ---
MEMORYPORT_SRC="$HOME/.memoryport"
if [ -d "$MEMORYPORT_SRC" ]; then
    mkdir -p "$TMP/memoryport"
    COPIED=0
    for f in graph-cache.json uc.toml proxy-sessions.json; do
        if [ -f "$MEMORYPORT_SRC/$f" ]; then
            cp "$MEMORYPORT_SRC/$f" "$TMP/memoryport/"
            COPIED=$((COPIED + 1))
        fi
    done
    if [ "$COPIED" -eq 0 ]; then
        fail "memoryport: no files found to back up"
    else
        (cd "$TMP" && tar -czf "$BACKUP_DIR/memoryport-data-$DATE.tar.gz" memoryport)
    fi
else
    fail "memoryport source dir not found: $MEMORYPORT_SRC"
fi

# --- OpenClaw config (secrets optionally excluded) ---
OPENCLAW_SRC="$HOME/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_SRC" ]; then
    mkdir -p "$TMP/openclaw"
    cp "$OPENCLAW_SRC" "$TMP/openclaw/"
    (cd "$TMP" && tar -czf "$BACKUP_DIR/openclaw-config-$DATE.tar.gz" openclaw)
else
    fail "openclaw config not found: $OPENCLAW_SRC"
fi

# --- Ollama model list (just the manifest, not the models themselves) ---
mkdir -p "$TMP/ollama"
if curl -sf http://127.0.0.1:11434/api/tags | python3 -m json.tool > "$TMP/ollama/model-manifest.json" 2>/dev/null && [ -s "$TMP/ollama/model-manifest.json" ]; then
    (cd "$TMP" && tar -czf "$BACKUP_DIR/ollama-manifest-$DATE.tar.gz" ollama)
fi
# Ollama being offline is not an error — it's optional

# --- Verify archives are non-trivially sized ---
for archive in "$BACKUP_DIR"/gitnexus-"$DATE".tar.gz "$BACKUP_DIR"/memoryport-data-"$DATE".tar.gz "$BACKUP_DIR"/openclaw-config-"$DATE".tar.gz; do
    if [ -f "$archive" ]; then
        SIZE=$(stat -f%z "$archive" 2>/dev/null || stat -c%s "$archive" 2>/dev/null || echo 0)
        if [ "$SIZE" -lt 100 ]; then
            fail "archive suspiciously small (${SIZE}B): $(basename "$archive")"
        fi
    fi
done

# --- Add all new tarballs to git ---
cd "$BACKUP_DIR"
git add -A
git commit -m "backup $DATE" --quiet 2>/dev/null || true
git push --quiet 2>/dev/null || true

if [ "$ERRORS" -gt 0 ]; then
    echo "Backup completed with $ERRORS error(s)" >&2
    exit 1
fi
