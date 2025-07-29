#!/bin/bash

# === Args ===
PLAN_ID="$1"
LOCAL_PORT="$2"
USERNAME="$3"
PASSWORD="$4"
UPSTREAM_HOST="$5"
UPSTREAM_PORT="$6"

CONFIG_DIR="/etc/3proxy/plans"
CONFIG_FILE="${CONFIG_DIR}/${PLAN_ID}.cfg"

mkdir -p "$CONFIG_DIR"

# === Kill any existing process using the port ===
EXISTING_PID=$(lsof -tiTCP:$LOCAL_PORT)
if [ -n "$EXISTING_PID" ]; then
  echo "🛑 Killing existing process on port $LOCAL_PORT (PID: $EXISTING_PID)"
  kill -9 "$EXISTING_PID"
fi

# === Build the parent line depending on upstream ===
case "$UPSTREAM_HOST" in
  dcp.proxies.fo|pr-us.proxies.fo|pr-eu.proxies.fo)
    # All use the same correct parent line order
    PARENT_LINE="parent 1000 http $UPSTREAM_HOST $UPSTREAM_PORT $USERNAME $PASSWORD"
    ;;
  *)
    echo "⚠️ Unknown upstream host: $UPSTREAM_HOST"
    exit 1
    ;;
esac

# === Generate the 3proxy config ===
cat << EOF > "$CONFIG_FILE"
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users $USERNAME:CL:$PASSWORD
auth strong
allow $USERNAME
$PARENT_LINE
proxy -n -a -p$LOCAL_PORT -i0.0.0.0 -e0.0.0.0
EOF

# === Launch 3proxy with the new config ===
echo "🚀 Starting 3proxy on port $LOCAL_PORT for plan $PLAN_ID"
nohup /usr/bin/3proxy "$CONFIG_FILE" >/dev/null 2>&1 &

echo "✅ 3proxy started successfully"
