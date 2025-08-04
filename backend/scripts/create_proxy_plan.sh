#!/bin/bash
# create_proxy_plan.sh - Create individual HTTP proxy plan with nginx integration

# === Args ===
PLAN_ID="$1"
LOCAL_PORT="$2"
USERNAME="$3"
PASSWORD="$4"
UPSTREAM_HOST="$5"
UPSTREAM_PORT="$6"
SUBDOMAIN="$7"

# Validate required arguments
if [ $# -lt 7 ]; then
    echo "❌ Usage: $0 PLAN_ID LOCAL_PORT USERNAME PASSWORD UPSTREAM_HOST UPSTREAM_PORT SUBDOMAIN"
    exit 1
fi

# Updated paths to match your setup
CONFIG_DIR="/etc/3proxy/plans"
CONFIG_FILE="${CONFIG_DIR}/${PLAN_ID}_${SUBDOMAIN}.cfg"
PROXY_LOG="/var/log/oceanproxy/proxies.json"

# Port ranges (2000 ports each)
declare -A PORT_RANGES
PORT_RANGES["usa"]="10000-11999"
PORT_RANGES["eu"]="12000-13999"
PORT_RANGES["alpha"]="14000-15999"
PORT_RANGES["beta"]="16000-17999"
PORT_RANGES["mobile"]="18000-19999"
PORT_RANGES["unlim"]="20000-21999"
PORT_RANGES["datacenter"]="22000-23999"
PORT_RANGES["gamma"]="24000-25999"
PORT_RANGES["delta"]="26000-27999"
PORT_RANGES["epsilon"]="28000-29999"
PORT_RANGES["zeta"]="30000-31999"
PORT_RANGES["eta"]="32000-33999"

# Public port mapping based on subdomain
declare -A PUBLIC_PORTS
PUBLIC_PORTS["usa"]="1337"
PUBLIC_PORTS["eu"]="1338"
PUBLIC_PORTS["alpha"]="9876"
PUBLIC_PORTS["beta"]="8765"
PUBLIC_PORTS["mobile"]="7654"
PUBLIC_PORTS["unlim"]="6543"
PUBLIC_PORTS["datacenter"]="1339"
PUBLIC_PORTS["gamma"]="5432"
PUBLIC_PORTS["delta"]="4321"
PUBLIC_PORTS["epsilon"]="3210"
PUBLIC_PORTS["zeta"]="2109"
PUBLIC_PORTS["eta"]="1098"

PUBLIC_PORT=${PUBLIC_PORTS[$SUBDOMAIN]}
PORT_RANGE=${PORT_RANGES[$SUBDOMAIN]}

# Create directories if they don't exist
mkdir -p "$CONFIG_DIR"
mkdir -p "/var/log/oceanproxy"

echo "🔧 Creating whitelabel HTTP proxy plan: $PLAN_ID [$SUBDOMAIN]"
echo "   👤 Username: $USERNAME"
echo "   🔌 Local Port: $LOCAL_PORT"
echo "   📊 Port Range: $PORT_RANGE (2000 ports max)"
echo "   🌐 Public Endpoint: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}"
echo "   📡 Upstream: $UPSTREAM_HOST:$UPSTREAM_PORT"

# === Validate port is within allowed range ===
IFS='-' read -r MIN_PORT MAX_PORT <<< "$PORT_RANGE"
if [[ $LOCAL_PORT -lt $MIN_PORT ]] || [[ $LOCAL_PORT -gt $MAX_PORT ]]; then
    echo "❌ Port $LOCAL_PORT is outside allowed range $PORT_RANGE for subdomain $SUBDOMAIN"
    exit 1
fi

# === Kill any existing process using the port ===
EXISTING_PID=$(lsof -tiTCP:$LOCAL_PORT 2>/dev/null)
if [ -n "$EXISTING_PID" ]; then
    echo "🛑 Killing existing process on port $LOCAL_PORT (PID: $EXISTING_PID)"
    kill -9 "$EXISTING_PID" 2>/dev/null
    sleep 1
fi

# === Remove any existing config files for this plan ===
rm -f "${CONFIG_DIR}/${PLAN_ID}.cfg" 2>/dev/null
rm -f "${CONFIG_DIR}/${PLAN_ID}_${SUBDOMAIN}.cfg" 2>/dev/null

# === Validate upstream host ===
case "$UPSTREAM_HOST" in
    dcp.proxies.fo|pr-us.proxies.fo|pr-eu.proxies.fo|proxy.nettify.xyz)
        echo "✅ Valid upstream host: $UPSTREAM_HOST"
        ;;
    blank|"")
        echo "⚠️ Blank proxy type - no upstream will be configured"
        UPSTREAM_HOST="blank"
        ;;
    *)
        echo "⚠️ Unknown upstream host: $UPSTREAM_HOST"
        echo "   Supported hosts: dcp.proxies.fo, pr-us.proxies.fo, pr-eu.proxies.fo, proxy.nettify.xyz, blank"
        exit 1
        ;;
esac

# === Generate the 3proxy config ===
echo "📝 Creating individual 3proxy config..."

if [[ "$UPSTREAM_HOST" == "blank" ]]; then
    # Blank proxy configuration (no upstream)
    cat << EOF > "$CONFIG_FILE"
# 3proxy config for whitelabel HTTP proxy (BLANK TYPE)
# Plan ID: $PLAN_ID
# User: $USERNAME
# Client endpoint: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}:${USERNAME}:${PASSWORD}
# Internal port: $LOCAL_PORT
# Upstream: NONE (blank proxy - direct connection)

nscache 65536
timeouts 10 20 60 300 300 1800 10 120
maxconn 2000

# Authentication for this specific user
users $USERNAME:CL:$PASSWORD
auth strong
allow $USERNAME

# HTTP proxy listening on port $LOCAL_PORT (no parent)
proxy -n -a -p$LOCAL_PORT -i0.0.0.0 -e0.0.0.0
EOF
else
    # Regular proxy configuration (with upstream)
    cat << EOF > "$CONFIG_FILE"
# 3proxy config for whitelabel HTTP proxy
# Plan ID: $PLAN_ID
# User: $USERNAME
# Client endpoint: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}:${USERNAME}:${PASSWORD}
# Internal port: $LOCAL_PORT
# Upstream: ${UPSTREAM_HOST}:${UPSTREAM_PORT}:${USERNAME}:${PASSWORD}

nscache 65536
timeouts 10 20 60 300 300 1800 10 120
maxconn 2000

# Authentication for this specific user
users $USERNAME:CL:$PASSWORD
auth strong
allow $USERNAME

# Parent proxy (upstream provider)
parent 1000 http $UPSTREAM_HOST $UPSTREAM_PORT $USERNAME $PASSWORD

# HTTP proxy listening on port $LOCAL_PORT
proxy -n -a -p$LOCAL_PORT -i0.0.0.0 -e0.0.0.0
EOF
fi

# Set proper permissions on config file
chmod 644 "$CONFIG_FILE"

# === Launch 3proxy with the new config ===
echo "🚀 Starting 3proxy on port $LOCAL_PORT for user $USERNAME"

# Use full path to 3proxy
PROXY_BIN="/usr/bin/3proxy"
if [[ ! -f "$PROXY_BIN" ]] && [[ -f "/usr/local/bin/3proxy" ]]; then
    PROXY_BIN="/usr/local/bin/3proxy"
fi

nohup "$PROXY_BIN" "$CONFIG_FILE" > "/var/log/oceanproxy/3proxy_${PLAN_ID}_${SUBDOMAIN}.log" 2>&1 &
PROXY_PID=$!

# === Verify startup ===
sleep 3

# Check if process is still running
if ! kill -0 "$PROXY_PID" 2>/dev/null; then
    echo "❌ 3proxy process failed to start"
    echo "📋 Check log: /var/log/oceanproxy/3proxy_${PLAN_ID}_${SUBDOMAIN}.log"
    echo "📋 Config file: $CONFIG_FILE"
    cat "/var/log/oceanproxy/3proxy_${PLAN_ID}_${SUBDOMAIN}.log" 2>/dev/null || echo "No log file found"
    exit 1
fi

# Check if port is listening
if ! netstat -tlnp 2>/dev/null | grep -q ":$LOCAL_PORT "; then
    echo "❌ 3proxy is not listening on port $LOCAL_PORT"
    kill -9 "$PROXY_PID" 2>/dev/null
    echo "📋 Check log: /var/log/oceanproxy/3proxy_${PLAN_ID}_${SUBDOMAIN}.log"
    echo "📋 Config file: $CONFIG_FILE"
    cat "/var/log/oceanproxy/3proxy_${PLAN_ID}_${SUBDOMAIN}.log" 2>/dev/null || echo "No log file found"
    exit 1
fi

echo "✅ 3proxy started successfully (PID: $PROXY_PID)"
echo "✅ Proxy plan $PLAN_ID is live and ready for clients!"
echo "🌐 Client connects to: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT} with credentials ${USERNAME}:${PASSWORD}"