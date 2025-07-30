#!/bin/bash

# Script to fix 3proxy forwarding issues - Simple working format

CONFIG_DIR="/etc/3proxy/plans"
PROXY_LOG="/var/log/oceanproxy/proxies.json"

echo "🔧 Fixing 3proxy forwarding issues..."

# Stop all 3proxy processes
echo "🛑 Stopping all 3proxy processes..."
sudo pkill -f 3proxy
sleep 2

# Clean up all existing config files
echo "🗑️  Cleaning up existing config files..."
sudo rm -f ${CONFIG_DIR}/*.cfg

# Install jq if not present
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq..."
    apt-get update && apt-get install -y jq
fi

echo "🔍 Processing proxy entries from log..."

# Process each valid entry and recreate configs
jq -c '.[]' "$PROXY_LOG" | while read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    auth_port=$(echo "$entry" | jq -r '.auth_port')
    local_port=$(echo "$entry" | jq -r '.local_port')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    
    echo "🔄 Processing: $plan_id [$subdomain] on port $local_port"
    
    # Skip if essential fields are missing
    if [ "$plan_id" = "null" ] || [ "$local_port" = "null" ] || [ "$auth_host" = "null" ]; then
        echo "   ⚠️  Skipping malformed entry"
        continue
    fi
    
    # Create proper config based on provider
    CONFIG_FILE="${CONFIG_DIR}/${plan_id}_${subdomain}.cfg"
    
    case "$auth_host" in
        proxy.nettify.xyz)
            echo "   🌐 Creating Nettify config (simple working format)..."
            cat > "$CONFIG_FILE" << EOF
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users $username:CL:$password
auth strong
allow $username
parent 1000 http $auth_host $auth_port $username $password
proxy -n -a -p$local_port -i0.0.0.0 -e0.0.0.0
EOF
            ;;
        dcp.proxies.fo|pr-us.proxies.fo|pr-eu.proxies.fo)
            echo "   🏢 Creating ProxiesFO config..."
            cat > "$CONFIG_FILE" << EOF
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users $username:CL:$password
auth strong
allow $username
parent 1000 http $auth_host $auth_port $username $password
proxy -n -a -p$local_port -i0.0.0.0 -e0.0.0.0
EOF
            ;;
        *)
            echo "   ❌ Unknown provider: $auth_host - skipping"
            continue
            ;;
    esac
    
    # Start 3proxy for this config
    echo "   🚀 Starting 3proxy on port $local_port..."
    nohup /usr/bin/3proxy "$CONFIG_FILE" > "/var/log/3proxy_${plan_id}_${subdomain}.log" 2>&1 &
    
    # Give it a moment to start
    sleep 1
    
    # Verify it's listening
    if netstat -tlnp 2>/dev/null | grep -q ":$local_port "; then
        echo "   ✅ Successfully started on port $local_port"
        
        # Show test commands
        if [ "$auth_host" = "proxy.nettify.xyz" ]; then
            echo "   🧪 Test command:"
            echo "      curl --proxy http://${username}:${password}@${subdomain}.oceanproxy.io:${local_port} http://httpbin.org/ip"
            echo "   📝 Note: Use base username format (no country extensions)"
        else
            echo "   🧪 Test command:"
            echo "      curl --proxy http://${username}:${password}@${subdomain}.oceanproxy.io:${local_port} http://httpbin.org/ip"
        fi
    else
        echo "   ❌ Failed to bind to port $local_port"
    fi
    
done

echo ""
echo "🎉 Fix completed!"
echo ""
echo "📊 Current status:"
echo "   Active 3proxy processes: $(ps aux | grep 3proxy | grep -v grep | wc -l)"
echo "   Config files created: $(ls -1 ${CONFIG_DIR}/*.cfg 2>/dev/null | wc -l)"
echo ""
echo "🔍 Listening ports:"
netstat -tlnp 2>/dev/null | grep 3proxy | awk '{print "   " $4}' | sort
echo ""
echo "✅ 3proxy forwarding fix completed!"
echo ""
echo "📝 Important: Nettify proxies use base username format only."
echo "   Example: curl --proxy http://username:password@alpha.oceanproxy.io:port http://httpbin.org/ip"
echo "   Country selection is handled automatically by Nettify."
