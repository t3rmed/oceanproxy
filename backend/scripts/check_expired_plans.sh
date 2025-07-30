#!/bin/bash
# check_expired_plans.sh - Check for expired proxy plans and optionally remove them
# Updated for whitelabel HTTP proxy system

PROXY_LOG="/var/log/oceanproxy/proxies.json"
CONFIG_DIR="/etc/3proxy/plans"
STREAM_CONFIG="/etc/nginx/stream.d"

# Command line options
DRY_RUN=false
AUTO_CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --cleanup)
            AUTO_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --cleanup    Automatically remove expired plans"
            echo "  --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Check for expired plans (read-only)"
            echo "  $0 --dry-run         # Show what would be cleaned up"
            echo "  $0 --cleanup         # Actually remove expired plans"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🔍 Checking for expired proxy plans..."

# Check if proxy log exists
if [ ! -f "$PROXY_LOG" ]; then
    echo "❌ Proxy log not found: $PROXY_LOG"
    exit 1
fi

# Check if log is empty
TOTAL_PLANS=$(jq length "$PROXY_LOG" 2>/dev/null || echo "0")
if [ "$TOTAL_PLANS" -eq 0 ]; then
    echo "📋 No plans found in proxy log"
    exit 0
fi

echo "📋 Found $TOTAL_PLANS total plans"

# Current timestamp
CURRENT_TIME=$(date +%s)

EXPIRED_COUNT=0
ACTIVE_COUNT=0
INVALID_COUNT=0
PLANS_TO_REMOVE=()

echo ""
echo "📊 Plan Analysis:"

# Process each plan
while IFS= read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    local_port=$(echo "$entry" | jq -r '.local_port')
    status=$(echo "$entry" | jq -r '.status // "active"')
    created_at=$(echo "$entry" | jq -r '.created_at // ""')
    expires_at=$(echo "$entry" | jq -r '.expires_at // ""')
    
    # Skip malformed entries
    if [ "$plan_id" = "null" ] || [ "$username" = "null" ]; then
        echo "   ⚠️ Invalid plan entry (missing plan_id or username)"
        ((INVALID_COUNT++))
        continue
    fi
    
    # Check if plan has expiration date
    if [ "$expires_at" = "" ] || [ "$expires_at" = "null" ]; then
        echo "   📋 Plan $plan_id ($username): No expiration date set"
        ((ACTIVE_COUNT++))
        continue
    fi
    
    # Convert expiration date to timestamp
    EXPIRE_TIME=$(date -d "$expires_at" +%s 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "   ⚠️ Plan $plan_id ($username): Invalid expiration date format: $expires_at"
        ((INVALID_COUNT++))
        continue
    fi
    
    # Check if expired
    if [ $CURRENT_TIME -gt $EXPIRE_TIME ]; then
        DAYS_EXPIRED=$(( (CURRENT_TIME - EXPIRE_TIME) / 86400 ))
        echo "   ❌ Plan $plan_id ($username): EXPIRED $DAYS_EXPIRED days ago (expired: $expires_at)"
        ((EXPIRED_COUNT++))
        PLANS_TO_REMOVE+=("$plan_id")
        
        # Check if 3proxy process is still running
        if ps aux | grep -v grep | grep -q "/etc/3proxy/plans/${plan_id}_${subdomain}.cfg"; then
            echo "      🔥 Process still running on port $local_port"
        fi
        
        # Check if config files still exist
        config_file="${CONFIG_DIR}/${plan_id}_${subdomain}.cfg"
        if [ -f "$config_file" ]; then
            echo "      📁 Config file exists: $config_file"
        fi
    else
        DAYS_REMAINING=$(( (EXPIRE_TIME - CURRENT_TIME) / 86400 ))
        if [ $DAYS_REMAINING -le 7 ]; then
            echo "   ⚠️ Plan $plan_id ($username): Expires in $DAYS_REMAINING days ($expires_at)"
        else
            echo "   ✅ Plan $plan_id ($username): Active (expires in $DAYS_REMAINING days)"
        fi
        ((ACTIVE_COUNT++))
    fi
    
done < <(jq -c '.[]' "$PROXY_LOG")

echo ""
echo "📈 Summary:"
echo "   ✅ Active plans: $ACTIVE_COUNT"
echo "   ❌ Expired plans: $EXPIRED_COUNT"
echo "   ⚠️ Invalid entries: $INVALID_COUNT"
echo "   📋 Total plans: $TOTAL_PLANS"

# If no expired plans, exit
if [ $EXPIRED_COUNT -eq 0 ]; then
    echo ""
    echo "🎉 No expired plans found! All systems clean."
    exit 0
fi

# Show what would be done
if [ $DRY_RUN = true ] || [ $AUTO_CLEANUP = false ]; then
    echo ""
    echo "🔄 Cleanup Actions (DRY RUN):"
    for plan_id in "${PLANS_TO_REMOVE[@]}"; do
        echo "   Would remove plan: $plan_id"
        
        # Find subdomain for this plan
        subdomain=$(jq -r --arg plan_id "$plan_id" '.[] | select(.plan_id == $plan_id) | .subdomain' "$PROXY_LOG")
        local_port=$(jq -r --arg plan_id "$plan_id" '.[] | select(.plan_id == $plan_id) | .local_port' "$PROXY_LOG")
        
        echo "     - Kill 3proxy process on port $local_port"
        echo "     - Remove config: ${CONFIG_DIR}/${plan_id}_${subdomain}.cfg"
        echo "     - Remove from proxy log"
        echo "     - Update nginx configuration"
    done
    
    if [ $AUTO_CLEANUP = false ]; then
        echo ""
        echo "💡 To actually remove expired plans, run:"
        echo "   $0 --cleanup"
    fi
    exit 0
fi

# Perform actual cleanup
if [ $AUTO_CLEANUP = true ]; then
    echo ""
    echo "🧹 Starting cleanup of expired plans..."
    
    CLEANED_COUNT=0
    
    for plan_id in "${PLANS_TO_REMOVE[@]}"; do
        echo "   🗑️ Removing expired plan: $plan_id"
        
        # Get plan details
        subdomain=$(jq -r --arg plan_id "$plan_id" '.[] | select(.plan_id == $plan_id) | .subdomain' "$PROXY_LOG")
        local_port=$(jq -r --arg plan_id "$plan_id" '.[] | select(.plan_id == $plan_id) | .local_port' "$PROXY_LOG")
        
        # Kill 3proxy process
        if ps aux | grep -v grep | grep -q "/etc/3proxy/plans/${plan_id}_${subdomain}.cfg"; then
            echo "     🛑 Killing 3proxy process on port $local_port"
            pkill -f "${plan_id}_${subdomain}.cfg"
        fi
        
        # Remove config file
        config_file="${CONFIG_DIR}/${plan_id}_${subdomain}.cfg"
        if [ -f "$config_file" ]; then
            echo "     📁 Removing config file: $config_file"
            rm -f "$config_file"
        fi
        
        # Remove log file
        log_file="/var/log/3proxy_${plan_id}_${subdomain}.log"
        if [ -f "$log_file" ]; then
            echo "     📋 Removing log file: $log_file"
            rm -f "$log_file"
        fi
        
        ((CLEANED_COUNT++))
    done
    
    # Update proxy log (remove expired plans)
    echo "   📝 Updating proxy log..."
    temp_file=$(mktemp)
    jq --argjson expired_plans "$(printf '%s\n' "${PLANS_TO_REMOVE[@]}" | jq -R . | jq -s .)" \
       'map(select(.plan_id as $id | $expired_plans | index($id) | not))' \
       "$PROXY_LOG" > "$temp_file" && mv "$temp_file" "$PROXY_LOG"
    
    # Rebuild nginx configuration
    echo "   🔄 Rebuilding nginx configuration..."
    ./automatic_proxy_manager.sh >/dev/null 2>&1
    
    echo ""
    echo "✅ Cleanup completed!"
    echo "   🗑️ Removed $CLEANED_COUNT expired plans"
    echo "   📋 Updated proxy log and nginx configuration"
fi
