#!/bin/bash
# ensure_proxies.sh - Health check and auto-restart for proxy instances
# Updated for whitelabel HTTP proxy system

PROXY_LOG="/var/log/oceanproxy/proxies.json"
CONFIG_DIR="/etc/3proxy/plans"

# Command line options
AUTO_RESTART=false
CHECK_CONNECTIVITY=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --restart)
            AUTO_RESTART=true
            shift
            ;;
        --check-connectivity)
            CHECK_CONNECTIVITY=true
            shift
            ;;
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --restart           Automatically restart failed proxy instances"
            echo "  --check-connectivity Test proxy connectivity with HTTP requests"
            echo "  --quiet, -q         Minimal output (only show issues)"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "What this script checks:"
            echo "  • 3proxy processes are running"
            echo "  • Ports are listening"
            echo "  • Config files exist"
            echo "  • Optional: HTTP connectivity test"
            echo ""
            echo "Examples:"
            echo "  $0                        # Basic health check"
            echo "  $0 --restart             # Auto-restart failed instances"
            echo "  $0 --check-connectivity  # Test HTTP connectivity"
            echo "  $0 --restart --quiet     # Silent auto-restart"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

[ $QUIET = false ] && echo "🔍 Ensuring all proxy instances are healthy..."

# Check if proxy log exists
if [ ! -f "$PROXY_LOG" ]; then
    echo "❌ Proxy log not found: $PROXY_LOG"
    exit 1
fi

TOTAL_PLANS=$(jq length "$PROXY_LOG" 2>/dev/null || echo "0")
if [ "$TOTAL_PLANS" -eq 0 ]; then
    [ $QUIET = false ] && echo "📋 No plans found in proxy log"
    exit 0
fi

[ $QUIET = false ] && echo "📋 Checking $TOTAL_PLANS proxy instances..."

# Counters
HEALTHY_COUNT=0
UNHEALTHY_COUNT=0
RESTARTED_COUNT=0
FAILED_RESTART_COUNT=0

# Process each plan
while IFS= read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    auth_port=$(echo "$entry" | jq -r '.auth_port')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    local_port=$(echo "$entry" | jq -r '.local_port')
    public_port=$(echo "$entry" | jq -r '.public_port')
    status=$(echo "$entry" | jq -r '.status // "active"')
    
    # Skip inactive plans
    if [ "$status" != "active" ]; then
        [ $QUIET = false ] && echo "   ⏭️ Skipping inactive plan: $plan_id"
        continue
    fi
    
    # Skip malformed entries
    if [ "$plan_id" = "null" ] || [ "$username" = "null" ] || [ "$local_port" = "null" ]; then
        echo "   ❌ Plan $plan_id: Invalid data"
        ((UNHEALTHY_COUNT++))
        continue
    fi
    
    [ $QUIET = false ] && echo "   🔍 Checking plan: $plan_id ($username) on port $local_port"
    
    PLAN_HEALTHY=true
    ISSUES=()
    
    # Check if config file exists
    config_file="${CONFIG_DIR}/${plan_id}_${subdomain}.cfg"
    if [ ! -f "$config_file" ]; then
        PLAN_HEALTHY=false
        ISSUES+=("missing config file")
    fi
    
    # Check if 3proxy process is running
    if ! ps aux | grep -v grep | grep -q "/etc/3proxy/plans/${plan_id}_${subdomain}.cfg"; then
        PLAN_HEALTHY=false
        ISSUES+=("process not running")
    fi
    
    # Check if port is listening
    if ! netstat -tlnp 2>/dev/null | grep -q ":$local_port "; then
        PLAN_HEALTHY=false
        ISSUES+=("port not listening")
    fi
    
    # Optional connectivity check
    if [ $CHECK_CONNECTIVITY = true ] && [ $PLAN_HEALTHY = true ]; then
        [ $QUIET = false ] && echo "      🧪 Testing HTTP connectivity..."
        if ! curl -x "127.0.0.1:$local_port" -U "$username:$password" \
             --connect-timeout 5 --max-time 10 --silent --fail \
             "http://httpbin.org/ip" >/dev/null 2>&1; then
            PLAN_HEALTHY=false
            ISSUES+=("connectivity test failed")
        fi
    fi
    
    # Report status
    if [ $PLAN_HEALTHY = true ]; then
        [ $QUIET = false ] && echo "      ✅ Healthy"
        ((HEALTHY_COUNT++))
    else
        issue_list=$(IFS=', '; echo "${ISSUES[*]}")
        echo "      ❌ Unhealthy: $issue_list"
        ((UNHEALTHY_COUNT++))
        
        # Auto-restart if requested
        if [ $AUTO_RESTART = true ]; then
            echo "      🔧 Attempting to restart..."
            
            # Kill existing process if any
            pkill -f "${plan_id}_${subdomain}.cfg" 2>/dev/null
            sleep 1
            
            # Recreate config if missing
            if [ ! -f "$config_file" ]; then
                echo "      📝 Recreating config file..."
                mkdir -p "$CONFIG_DIR"
                cat << EOF > "$config_file"
# 3proxy config for whitelabel HTTP proxy
# Plan ID: $plan_id - Auto-recreated by ensure_proxies.sh
# User: $username

nscache 65536
timeouts 1 5 30 60 180 1800 15 60

# Authentication for this specific user
users $username:CL:$password
auth strong
allow $username

# Parent proxy (upstream provider)
parent 1000 http $auth_host $auth_port $username $password

# HTTP proxy listening on port $local_port
proxy -n -a -p$local_port -i0.0.0.0 -e0.0.0.0
EOF
            fi
            
            # Start 3proxy
            nohup /usr/bin/3proxy "$config_file" > "/var/log/3proxy_${plan_id}_${subdomain}.log" 2>&1 &
            sleep 2
            
            # Verify restart
            if ps aux | grep -v grep | grep -q "/etc/3proxy/plans/${plan_id}_${subdomain}.cfg" && \
               netstat -tlnp 2>/dev/null | grep -q ":$local_port "; then
                echo "      ✅ Successfully restarted"
                ((RESTARTED_COUNT++))
            else
                echo "      ❌ Failed to restart"
                echo "      📋 Check log: /var/log/3proxy_${plan_id}_${subdomain}.log"
                ((FAILED_RESTART_COUNT++))
            fi
        fi
    fi
    
done < <(jq -c '.[]' "$PROXY_LOG")

# Summary
echo ""
echo "📊 Health Check Summary:"
echo "   ✅ Healthy instances: $HEALTHY_COUNT"
echo "   ❌ Unhealthy instances: $UNHEALTHY_COUNT"

if [ $AUTO_RESTART = true ]; then
    echo "   🔧 Successfully restarted: $RESTARTED_COUNT"
    echo "   ❌ Failed to restart: $FAILED_RESTART_COUNT"
fi

echo "   📋 Total checked: $TOTAL_PLANS"

# Check nginx status
echo ""
echo "🔍 System Status:"
nginx_status="unknown"
if systemctl is-active nginx >/dev/null 2>&1; then
    nginx_status="✅ Running"
else
    nginx_status="❌ Not running"
fi
echo "   Nginx: $nginx_status"

active_processes=$(ps aux | grep 3proxy | grep -v grep | wc -l)
echo "   Active 3proxy processes: $active_processes"

# Final result
echo ""
if [ $UNHEALTHY_COUNT -eq 0 ]; then
    echo "🎉 All proxy instances are healthy!"
    exit 0
else
    if [ $AUTO_RESTART = true ]; then
        if [ $FAILED_RESTART_COUNT -eq 0 ]; then
            echo "✅ All issues have been automatically resolved!"
            exit 0
        else
            echo "⚠️ Some issues remain after restart attempts"
            echo "💡 Check individual logs for failed instances"
            exit 1
        fi
    else
        echo "⚠️ Found $UNHEALTHY_COUNT unhealthy instances"
        echo "💡 Run with --restart to automatically fix issues"
        exit 1
    fi
fi
