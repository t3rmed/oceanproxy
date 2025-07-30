#!/bin/bash

# Script to consolidate multiple plans by type into shared ports

PROXY_LOG="/var/log/oceanproxy/proxies.json"
CONFIG_DIR="/etc/3proxy/plans"
TEMP_DIR="/tmp/plan_consolidation"

echo "🔄 Consolidating proxy plans by type..."

# Stop all existing 3proxy processes
echo "🛑 Stopping all existing 3proxy processes..."
sudo pkill -f 3proxy
sleep 2

# Clean up existing configs
echo "🗑️  Cleaning up existing individual configs..."
sudo rm -f ${CONFIG_DIR}/*.cfg

# Create temp directory for processing
mkdir -p "$TEMP_DIR"
rm -f "$TEMP_DIR"/*

# Install jq if not present
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq..."
    apt-get update && apt-get install -y jq
fi

echo "📋 Analyzing proxy plans..."

# Define port mapping for each plan type
declare -A PORT_MAP
PORT_MAP["proxy.nettify.xyz_alpha"]="9876"
PORT_MAP["proxy.nettify.xyz_beta"]="8765"
PORT_MAP["proxy.nettify.xyz_mobile"]="7654"
PORT_MAP["proxy.nettify.xyz_unlim"]="6543"
PORT_MAP["pr-us.proxies.fo_usa"]="1337"
PORT_MAP["pr-eu.proxies.fo_eu"]="1338"
PORT_MAP["dcp.proxies.fo_datacenter"]="8000"

# Define correct upstream ports for each provider
declare -A UPSTREAM_PORTS
UPSTREAM_PORTS["proxy.nettify.xyz"]="8080"
UPSTREAM_PORTS["pr-us.proxies.fo"]="1337"
UPSTREAM_PORTS["pr-eu.proxies.fo"]="1338"
UPSTREAM_PORTS["dcp.proxies.fo"]="8000"

# Group plans by provider and subdomain
jq -c '.[]' "$PROXY_LOG" | while read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    auth_port=$(echo "$entry" | jq -r '.auth_port')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    
    # Skip malformed entries
    if [ "$plan_id" = "null" ] || [ "$auth_host" = "null" ] || [ "$subdomain" = "null" ]; then
        continue
    fi
    
    # Create group key based on provider and subdomain
    GROUP_KEY="${auth_host}_${subdomain}"
    
    # Append plan info to group file
    echo "${plan_id}|${username}|${password}|${auth_host}|${auth_port}" >> "$TEMP_DIR/$GROUP_KEY"
done

echo ""
echo "📊 Plan groups found:"
for group_file in "$TEMP_DIR"/*; do
    if [ -f "$group_file" ]; then
        group_name=$(basename "$group_file")
        plan_count=$(wc -l < "$group_file")
        port=${PORT_MAP[$group_name]}
        echo "   $group_name: $plan_count plans → Port $port"
    fi
done

echo ""
echo "🔧 Creating consolidated configs..."

# Process each group
for group_file in "$TEMP_DIR"/*; do
    if [ ! -f "$group_file" ]; then
        continue
    fi
    
    group_name=$(basename "$group_file")
    local_port=${PORT_MAP[$group_name]}
    
    if [ -z "$local_port" ]; then
        echo "   ⚠️  No port mapping for group: $group_name - skipping"
        continue
    fi
    
    echo "   🔄 Processing group: $group_name (Port $local_port)"
    
    # Get first entry for upstream config
    first_line=$(head -n1 "$group_file")
    IFS='|' read -r first_plan_id first_username first_password auth_host original_auth_port <<< "$first_line"
    
    # Use correct upstream port based on provider
    correct_upstream_port=${UPSTREAM_PORTS[$auth_host]}
    if [ -z "$correct_upstream_port" ]; then
        echo "   ⚠️  No upstream port mapping for provider: $auth_host - using original port"
        correct_upstream_port=$original_auth_port
    fi
    
    echo "   📡 Upstream: $auth_host:$correct_upstream_port"
    
    # Create config file
    config_file="${CONFIG_DIR}/${group_name}_consolidated.cfg"
    
    # Start config with common settings
    cat > "$config_file" << EOF
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
EOF
    
    # Add all users for this group
    while IFS='|' read -r plan_id username password host port_unused; do
        echo "users $username:CL:$password" >> "$config_file"
    done < "$group_file"
    
    # Add auth and allow settings
    echo "auth strong" >> "$config_file"
    
    # Add allow entries for all users
    while IFS='|' read -r plan_id username password host port_unused; do
        echo "allow $username" >> "$config_file"
    done < "$group_file"
    
    # Add parent and proxy config with correct upstream port
    cat >> "$config_file" << EOF
parent 1000 http $auth_host $correct_upstream_port $first_username $first_password
proxy -n -a -p$local_port -i0.0.0.0 -e0.0.0.0
EOF
    
    echo "      ✅ Created config: $config_file"
    echo "      👥 Users: $(wc -l < "$group_file")"
    echo "      🔗 Parent: $auth_host:$correct_upstream_port"
    
    # Start 3proxy for this group
    echo "      🚀 Starting 3proxy on port $local_port..."
    nohup /usr/bin/3proxy "$config_file" > "/var/log/3proxy_${group_name}.log" 2>&1 &
    
    # Verify startup
    sleep 1
    if netstat -tlnp 2>/dev/null | grep -q ":$local_port "; then
        echo "      ✅ Successfully started on port $local_port"
        
        # Show example test command
        example_user=$(head -n1 "$group_file" | cut -d'|' -f2)
        example_pass=$(head -n1 "$group_file" | cut -d'|' -f3)
        subdomain=$(echo "$group_name" | cut -d'_' -f2)
        
        echo "      🧪 Test command:"
        echo "         curl --proxy http://${example_user}:${example_pass}@${subdomain}.oceanproxy.io:${local_port} http://httpbin.org/ip"
    else
        echo "      ❌ Failed to start on port $local_port"
        echo "      📋 Check log: /var/log/3proxy_${group_name}.log"
    fi
    
    echo ""
done

# Clean up temp files
rm -rf "$TEMP_DIR"

echo "🎉 Consolidation completed!"
echo ""
echo "📊 Summary:"
echo "   Active 3proxy processes: $(ps aux | grep 3proxy | grep -v grep | wc -l)"
echo "   Consolidated configs: $(ls -1 ${CONFIG_DIR}/*_consolidated.cfg 2>/dev/null | wc -l)"
echo ""
echo "🔍 Active ports:"
netstat -tlnp 2>/dev/null | grep 3proxy | awk '{print "   " $4}' | sort
echo ""
echo "📝 Benefits:"
echo "   - All plans of same type share one port"
echo "   - Reduced resource usage"
echo "   - Simplified port management"
echo "   - Multiple users per proxy instance"
echo "   - Correct upstream port mapping"
echo ""
echo "✅ All done!"
