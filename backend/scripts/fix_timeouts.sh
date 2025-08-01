#!/bin/bash
# fix_timeouts_and_restart.sh — Increase timeouts for stability

set -e

CONFIG_DIR="/etc/3proxy/plans"
UPDATED=0

echo "🚀 Patching 3proxy configs for better timeout tolerance..."

for cfg in "$CONFIG_DIR"/*.cfg; do
    if grep -q '^timeouts ' "$cfg"; then
        echo "⚙️  Updating timeouts in $(basename "$cfg")"
        sed -i 's/^timeouts .*/timeouts 10 20 60 300 300 1800 10 120/' "$cfg"
        UPDATED=1
    fi

    if ! grep -q '^maxconn' "$cfg"; then
        echo "➕ Adding maxconn to $(basename "$cfg")"
        sed -i '1imaxconn 2000' "$cfg"
        UPDATED=1
    fi
done

if [ "$UPDATED" -eq 1 ]; then
    echo "🔄 Restarting all 3proxy instances..."
    pkill -f 3proxy || true
    sleep 2
    ./activate_all_proxies.sh
else
    echo "✅ No updates needed. All configs already patched."
fi

echo "🎯 Done. You may now retest client curl or proxy checks."

