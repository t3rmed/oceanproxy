#!/bin/bash

# Script to fix existing proxy plans using individual configs (no consolidation)

PROXY_LOG="/var/log/oceanproxy/proxies.json"
SCRIPT_DIR="/root/oceanproxy-api/backend/scripts"
CONFIG_DIR="/etc/3proxy/plans"

echo "🔧 Fixing existing proxy plans with individual configs..."

# Check if proxy log exists
if [ ! -f "$PROXY_LOG" ]; then
    echo "❌ Proxy log file not found: $PROXY_LOG"
    exit 1
fi

# Check if create_proxy_plan.sh exists
if [ ! -f "$SCRIPT_DIR/create_proxy_plan.sh" ]; then
    echo "❌ create_proxy_plan.sh script not found: $SCRIPT_DIR/create_proxy_plan.sh"
    exit 1
fi

# Make sure the script is executable
chmod +x "$SCRIPT_DIR/create_proxy_plan.sh"

# Install jq if not present
if ! command -v jq &> /dev/null; then
    echo "❌ jq is required but not installed. Installing..."
    apt-get update && apt-get install -y jq
fi

echo "📋 Reading proxy entries from $PROXY_LOG"

# Stop all existing 3proxy processes
echo "🛑 Stopping all existing 3proxy processes..."
sudo pkill -f 3proxy
sleep 2

# Clean up all existing configs (individual and consolidated)
echo "🗑️ Cleaning up all existing configs..."
sudo rm -f ${CONFIG_DIR}/*.cfg

# Count plans processed
TOTAL_PLANS=0
SUCCESSFUL_PLANS=0
FAILED_PLANS=0

# Process each proxy entry
jq -r '.[] | [.plan_id, .local_port, .username, .password, .auth_host, .auth_port, .subdomain] | @csv' "$PROXY_LOG" | while IFS=',' read -r plan_id local_port username password auth_host auth_port subdomain; do
    
    # Remove quotes from CSV output
    plan_id=$(echo "$plan_id" | tr -d '"')
    local_port=$(echo "$local_port" | tr -d '"')
    username=$(echo "$username" | tr -d '"')
    password=$(echo "$password" | tr -d '"')
    auth_host=$(echo "$auth_host" | tr -d '"')
    auth_port=$(echo "$auth_port" | tr -d '"')
    subdomain=$(echo "$subdomain" | tr -d '"')
    
    ((TOTAL_PLANS++))
    
    echo "🔄 Processing plan: $plan_id [$subdomain]"
    echo "   Local Port: $local_port"
    echo "   Username: $username"
    echo "   Auth Host: $auth_host:$auth_port"
    
    # Create individual proxy plan
    echo "   🚀 Creating individual proxy..."
    "$SCRIPT_DIR/create_proxy_plan.sh" "$plan_id" "$local_port" "$username" "$password" "$auth_host" "$auth_port" "$subdomain"
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Successfully created individual plan $plan_id"
        ((SUCCESSFUL_PLANS++))
        
        echo "   🧪 Test command:"
        echo "      curl --proxy http://${username}:${password}@${subdomain}.oceanproxy.io:${local_port} http://httpbin.org/ip"
    else
        echo "   ❌ Failed to create plan $plan_id"
        ((FAILED_PLANS++))
    fi
    
    echo "   ----------------------------------------"
    sleep 1
done

echo ""
echo "🎉 Finished processing all proxy plans!"
echo ""
echo "📊 Individual Plan Summary:"
echo "   Total plans processed: $TOTAL_PLANS"
echo "   Successfully created: $SUCCESSFUL_PLANS" 
echo "   Failed: $FAILED_PLANS"
echo ""
echo "📊 System Status:"
echo "   Active 3proxy processes: $(ps aux | grep 3proxy | grep -v grep | wc -l)"
echo "   Individual config files: $(ls -1 ${CONFIG_DIR}/*.cfg 2>/dev/null | wc -l)"
echo ""
echo "🔍 Active ports:"
netstat -tlnp 2>/dev/null | grep 3proxy | awk '{print "   " $4}' | sort
echo ""
echo "📋 Individual configs created:"
ls -la ${CONFIG_DIR}/*.cfg 2>/dev/null | awk '{print "   " $9}' | sed 's|.*/||'
echo ""
echo "💡 Benefits of individual configs:"
echo "   - Each plan has its own port and process"
echo "   - No credential conflicts between plans"
echo "   - Independent authentication per plan"
echo "   - Easy to manage individual plans"
echo ""
echo "✅ All done! Your plans are now using individual configs."
