#!/bin/bash
# backup-workspace.sh — back up GitNexus config + MemoryPort data to this repo
# Run from the workspace-backup directory
set -euo pipefail

DATE=$(date -u +%Y-%m-%dT%H%M%SZ)
BACKUP_DIR="$(pwd)"
TMP=$(mktemp -d)

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# --- GitNexus ---
mkdir -p "$TMP/gitnexus"
cp -r ~/.gitnexus/* "$TMP/gitnexus/" 2>/dev/null || true
(cd "$TMP" && tar -czf "$BACKUP_DIR/gitnexus-$DATE.tar.gz" gitnexus)
echo "✓ gitnexus-backup: $(du -sh "$BACKUP_DIR/gitnexus-$DATE.tar.gz" | cut -f1)"

# --- MemoryPort data (not the massive index) ---
mkdir -p "$TMP/memoryport"
for f in graph-cache.json uc.toml env.sh registry.json; do
    cp "~/.memoryport/$f" "$TMP/memoryport/" 2>/dev/null || true
done
(cd "$TMP" && tar -czf "$BACKUP_DIR/memoryport-data-$DATE.tar.gz" memoryport)
echo "✓ memoryport-data-backup: $(du -sh "$BACKUP_DIR/memoryport-data-$DATE.tar.gz" | cut -f1)"

# --- OpenClaw config (secrets optionally excluded) ---
mkdir -p "$TMP/openclaw"
cp ~/.openclaw/openclaw.json "$TMP/openclaw/" 2>/dev/null || true
(cd "$TMP" && tar -czf "$BACKUP_DIR/openclaw-config-$DATE.tar.gz" openclaw)
echo "✓ openclaw-config-backup: $(du -sh "$BACKUP_DIR/openclaw-config-$DATE.tar.gz" | cut -f1)"

# --- Ollama model list (just the manifest, not the models themselves) ---
mkdir -p "$TMP/ollama"
curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | python3 -m json.tool > "$TMP/ollama/model-manifest.json" || true
if [ -s "$TMP/ollama/model-manifest.json" ]; then
    (cd "$TMP" && tar -czf "$BACKUP_DIR/ollama-manifest-$DATE.tar.gz" ollama)
    echo "✓ ollama-manifest-backup: $(du -sh "$BACKUP_DIR/ollama-manifest-$DATE.tar.gz" | cut -f1)"
else
    echo "⚠ ollama not running, skipping manifest"
fi

# --- Add all new tarballs to git ---
git add -A
git commit -m "backup $DATE" --quiet 2>/dev/null || true
git push 2>/dev/null && echo "✓ pushed to remote" || echo "⚠ remote not configured, commit only"

echo ""
echo "Done. Run 'git push' manually if remote is configured."
