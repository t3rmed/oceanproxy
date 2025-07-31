#!/bin/bash
# cleanup_invalid_plans.sh - Remove broken, orphaned, or invalid proxy plans
# Updated for whitelabel HTTP proxy system with duplicate and port conflict detection

PROXY_LOG="/var/log/oceanproxy/proxies.json"
CONFIG_DIR="/etc/3proxy/plans"

# Command line options
DRY_RUN=false
AUTO_FIX=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --fix)
            AUTO_FIX=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --fix        Automatically fix/remove invalid plans"
            echo "  --help       Show this help message"
            echo ""
            echo "What this script checks:"
            echo "  • Plans with missing config files"
            echo "  • Plans with dead 3proxy processes"
            echo "  • Plans with ports not listening"
            echo "  • Duplicate entries (same plan_id + subdomain)"
            echo "  • Port conflicts (multiple plans on same port)"
            echo "  • Invalid data (missing local_host, expires_at=0, created_at=0)"
            echo "  • Orphaned config files not in proxy log"
            echo "  • Orphaned 3proxy processes"
            echo ""
            echo "Examples:"
            echo "  $0                    # Check for issues (read-only)"
            echo "  $0 --dry-run         # Show what would be fixed"
            echo "  $0 --fix             # Actually fix issues"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🔍 Checking for invalid/broken proxy plans..."

# Arrays to track issues
MISSING_CONFIGS=()
DEAD_PROCESSES=()
NOT_LISTENING=()
ORPHANED_CONFIGS=()
ORPHANED_PROCESSES=()
INVALID_DATA=()
DUPLICATE_ENTRIES=()
PORT_CONFLICTS=()

# Check if proxy log exists
if [ ! -f "$PROXY_LOG" ]; then
    echo "❌ Proxy log not found: $PROXY_LOG"
    exit 1
fi

TOTAL_PLANS=$(jq length "$PROXY_LOG" 2>/dev/null || echo "0")
echo "📋 Found $TOTAL_PLANS plans in proxy log"

echo ""
echo "🔍 Analyzing proxy plans for duplicates and invalid data..."

# Arrays to track duplicates and port usage
declare -A SEEN_PLANS
declare -A PORT_USAGE
declare -A PLAN_ENTRIES

# First pass: identify duplicates, invalid data, and port conflicts
while IFS= read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    auth_port=$(echo "$entry" | jq -r '.auth_port')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    local_port=$(echo "$entry" | jq -r '.local_port')
    local_host=$(echo "$entry" | jq -r '.local_host')
    expires_at=$(echo "$entry" | jq -r '.expires_at')
    created_at=$(echo "$entry" | jq -r '.created_at')
    status=$(echo "$entry" | jq -r '.status // "active"')
    
    # Check for invalid data
    if [ "$plan_id" = "null" ] || [ "$username" = "null" ] || [ "$local_port" = "null" ] || [ "$subdomain" = "null" ]; then
        echo "   ❌ Plan has null fields: plan_id=$plan_id, username=$username, port=$local_port, subdomain=$subdomain"
        INVALID_DATA+=("$plan_id:null_fields")
        continue
    fi
    
    # Check for incomplete entries (missing local_host, expires_at=0, created_at=0)
    if [ "$local_host" = "" ] || [ "$local_host" = "null" ] || [ "$expires_at" = "0" ] || [ "$created_at" = "0" ]; then
        echo "   ❌ Plan has incomplete data: $plan_id ($username) - local_host='$local_host', expires_at=$expires_at, created_at=$created_at"
        INVALID_DATA+=("$plan_id:incomplete:$subdomain")
        continue
    fi
    
    # Check for duplicates (same plan_id + subdomain)
    plan_key="${plan_id}_${subdomain}"
    if [ -n "${SEEN_PLANS[$plan_key]}" ]; then
        echo "   ❌ Duplicate entry found: $plan_id ($subdomain) - keeping newer entry"
        DUPLICATE_ENTRIES+=("$plan_key")
        
        # Compare timestamps and keep the newer one
        existing_entry="${PLAN_ENTRIES[$plan_key]}"
        existing_created=$(echo "$existing_entry" | jq -r '.created_at')
        
        if [ "$created_at" -gt "$existing_created" ]; then
            PLAN_ENTRIES[$plan_key]="$entry"
        fi
    else
        SEEN_PLANS[$plan_key]=1
        PLAN_ENTRIES[$plan_key]="$entry"
    fi
    
    # Check for port conflicts
    if [ -n "${PORT_USAGE[$local_port]}" ]; then
        echo "   ❌ Port conflict: Port $local_port used by multiple plans: ${PORT_USAGE[$local_port]} and $plan_id"
        PORT_CONFLICTS+=("$local_port:$plan_id:${PORT_USAGE[$local_port]}")
    else
        PORT_USAGE[$local_port]="$plan_id"
    fi
    
done < <(jq -c '.[]' "$PROXY_LOG" 2>/dev/null)

echo ""
echo "🔍 Checking remaining valid plans..."

# Second pass: check valid plans for missing configs and dead processes
for plan_key in "${!PLAN_ENTRIES[@]}"; do
    entry="${PLAN_ENTRIES[$plan_key]}"
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    local_port=$(echo "$entry" | jq -r '.local_port')
    
    echo "   🔍 Checking valid plan: $plan_id ($username) on port $local_port"
    
    # Check if config file exists
    config_file="${CONFIG_DIR}/${plan_id}_${subdomain}.cfg"
    if [ ! -f "$config_file" ]; then
        echo "      ❌ Missing config file: $config_file"
        MISSING_CONFIGS+=("$plan_id:$subdomain:$local_port")
    fi
    
    # Check if 3proxy process is running
    if ! ps aux | grep -v grep | grep -q "/etc/3proxy/plans/${plan_id}_${subdomain}.cfg"; then
        echo "      ❌ 3proxy process not running"
        DEAD_PROCESSES+=("$plan_id:$subdomain:$local_port")
    fi
    
    # Check if port is listening
    if ! netstat -tlnp 2>/dev/null | grep -q ":$local_port "; then
        echo "      ❌ Port $local_port not listening"
        NOT_LISTENING+=("$plan_id:$subdomain:$local_port")
    fi
done

echo ""
echo "🔍 Checking for orphaned files and processes..."

# Check for orphaned config files
if [ -d "$CONFIG_DIR" ]; then
    for config_file in "$CONFIG_DIR"/*.cfg; do
        [ -f "$config_file" ] || continue
        
        filename=$(basename "$config_file" .cfg)
        plan_id=$(echo "$filename" | cut -d'_' -f1)
        
        # Check if this plan exists in our cleaned plan list
        plan_exists=false
        for plan_key in "${!PLAN_ENTRIES[@]}"; do
            if [[ "$plan_key" == "${plan_id}_"* ]]; then
                plan_exists=true
                break
            fi
        done
        
        if [ "$plan_exists" = false ]; then
            echo "   🗑️ Orphaned config file: $config_file (plan not in cleaned log)"
            ORPHANED_CONFIGS+=("$config_file")
        fi
    done
fi

# Check for orphaned 3proxy processes
ps aux | grep 3proxy | grep -v grep | while read -r line; do
    config_path=$(echo "$line" | grep -o '/etc/3proxy/plans/[^[:space:]]*\.cfg')
    if [ -n "$config_path" ]; then
        filename=$(basename "$config_path" .cfg)
        plan_id=$(echo "$filename" | cut -d'_' -f1)
        pid=$(echo "$line" | awk '{print $2}')
        
        # Check if this plan exists in our cleaned plan list
        plan_exists=false
        for plan_key in "${!PLAN_ENTRIES[@]}"; do
            if [[ "$plan_key" == "${plan_id}_"* ]]; then
                plan_exists=true
                break
            fi
        done
        
        if [ "$plan_exists" = false ]; then
            echo "   🔥 Orphaned 3proxy process: PID $pid ($config_path)"
            ORPHANED_PROCESSES+=("$pid:$config_path")
        fi
    fi
done

echo ""
echo "📊 Issues Found:"
echo "   ❌ Invalid/incomplete data entries: ${#INVALID_DATA[@]}"
echo "   🔄 Duplicate entries: ${#DUPLICATE_ENTRIES[@]}"
echo "   ⚠️ Port conflicts: ${#PORT_CONFLICTS[@]}"
echo "   📁 Missing config files: ${#MISSING_CONFIGS[@]}"
echo "   💀 Dead processes: ${#DEAD_PROCESSES[@]}"
echo "   🔇 Ports not listening: ${#NOT_LISTENING[@]}"
echo "   🗑️ Orphaned config files: ${#ORPHANED_CONFIGS[@]}"
echo "   🔥 Orphaned processes: ${#ORPHANED_PROCESSES[@]}"

# Calculate total issues
TOTAL_ISSUES=$((${#INVALID_DATA[@]} + ${#DUPLICATE_ENTRIES[@]} + ${#PORT_CONFLICTS[@]} + ${#MISSING_CONFIGS[@]} + ${#DEAD_PROCESSES[@]} + ${#NOT_LISTENING[@]} + ${#ORPHANED_CONFIGS[@]} + ${#ORPHANED_PROCESSES[@]}))

if [ $TOTAL_ISSUES -eq 0 ]; then
    echo ""
    echo "🎉 No issues found! Your proxy system is clean."
    exit 0
fi

# Show what would be done
if [ $DRY_RUN = true ] || [ $AUTO_FIX = false ]; then
    echo ""
    echo "🔄 Fixes that would be applied:"
    
    # Invalid data
    for item in "${INVALID_DATA[@]}"; do
        IFS=':' read -r plan_id issue_type subdomain <<< "$item"
        echo "   🗑️ Would remove invalid entry: $plan_id ($issue_type)"
    done
    
    # Duplicates
    for plan_key in "${DUPLICATE_ENTRIES[@]}"; do
        echo "   🔄 Would remove duplicate entries for: $plan_key (keeping newest)"
    done
    
    # Port conflicts
    for item in "${PORT_CONFLICTS[@]}"; do
        IFS=':' read -r port plan1 plan2 <<< "$item"
        echo "   ⚠️ Would resolve port conflict on $port between $plan1 and $plan2"
    done
    
    # Missing configs
    for item in "${MISSING_CONFIGS[@]}"; do
        IFS=':' read -r plan_id subdomain local_port <<< "$item"
        echo "   📝 Would recreate config for plan: $plan_id"
    done
    
    # Dead processes
    for item in "${DEAD_PROCESSES[@]}"; do
        IFS=':' read -r plan_id subdomain local_port <<< "$item"
        echo "   🚀 Would restart 3proxy for plan: $plan_id on port $local_port"
    done
    
    # Orphaned configs
    for config_file in "${ORPHANED_CONFIGS[@]}"; do
        echo "   🗑️ Would remove orphaned config: $config_file"
    done
    
    # Orphaned processes
    for item in "${ORPHANED_PROCESSES[@]}"; do
        IFS=':' read -r pid config_path <<< "$item"
        echo "   🔥 Would kill orphaned process: PID $pid ($config_path)"
    done
    
    if [ $AUTO_FIX = false ]; then
        echo ""
        echo "💡 To actually fix these issues, run:"
        echo "   $0 --fix"
    fi
    exit 0
fi

# Perform fixes
if [ $AUTO_FIX = true ]; then
    echo ""
    echo "🔧 Starting automatic fixes..."
    
    FIXED_COUNT=0
    
    # First: Create cleaned proxy log with only valid, non-duplicate entries
    echo "   🔄 Creating cleaned proxy log..."
    cleaned_entries=()
    for plan_key in "${!PLAN_ENTRIES[@]}"; do
        cleaned_entries+=("${PLAN_ENTRIES[$plan_key]}")
    done
    
    # Write cleaned log
    temp_file=$(mktemp)
    printf '%s\n' "${cleaned_entries[@]}" | jq -s '.' > "$temp_file" && mv "$temp_file" "$PROXY_LOG"
    echo "      ✅ Cleaned proxy log (removed duplicates and invalid entries)"
    ((FIXED_COUNT++))
    
    # Fix missing configs and restart processes
    for item in "${MISSING_CONFIGS[@]}"; do
        IFS=':' read -r plan_id subdomain local_port <<< "$item"
        echo "   🔧 Fixing plan: $plan_id"
        
        # Get plan details from cleaned data
        plan_key="${plan_id}_${subdomain}"
        if [ -n "${PLAN_ENTRIES[$plan_key]}" ]; then
            plan_data="${PLAN_ENTRIES[$plan_key]}"
            username=$(echo "$plan_data" | jq -r '.username')
            password=$(echo "$plan_data" | jq -r '.password')
            auth_host=$(echo "$plan_data" | jq -r '.auth_host')
            auth_port=$(echo "$plan_data" | jq -r '.auth_port')
            
            # Recreate config file  
            config_file="${CONFIG_DIR}/${plan_id}_${subdomain}.cfg"
            mkdir -p "$CONFIG_DIR"
            cat << EOF > "$config_file"
# 3proxy config for whitelabel HTTP proxy
# Plan ID: $plan_id - Auto-recreated by cleanup script
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
            
            # Kill any existing process on this port
            EXISTING_PID=$(lsof -tiTCP:$local_port 2>/dev/null)
            if [ -n "$EXISTING_PID" ]; then
                kill -9 "$EXISTING_PID" 2>/dev/null
                sleep 1
            fi
            
            # Start 3proxy
            nohup /usr/bin/3proxy "$config_file" > "/var/log/3proxy_${plan_id}_${subdomain}.log" 2>&1 &
            sleep 1
            
            if netstat -tlnp 2>/dev/null | grep -q ":$local_port "; then
                echo "      ✅ Fixed and restarted successfully"
                ((FIXED_COUNT++))
            else
                echo "      ❌ Failed to restart"
            fi
        fi
    done
    
    # Clean up orphaned configs
    for config_file in "${ORPHANED_CONFIGS[@]}"; do
        echo "   🗑️ Removing orphaned config: $config_file"
        rm -f "$config_file"
        ((FIXED_COUNT++))
    done
    
    # Kill orphaned processes
    for item in "${ORPHANED_PROCESSES[@]}"; do
        IFS=':' read -r pid config_path <<< "$item"
        echo "   🔥 Killing orphaned process: PID $pid"
        kill -9 "$pid" 2>/dev/null
        ((FIXED_COUNT++))
    done
    
    echo ""
    echo "✅ Cleanup completed!"
    echo "   🔧 Applied $FIXED_COUNT fixes"
    echo "   📋 Your proxy system should now be clean"
    
    # Show final status
    echo ""
    echo "🔍 Final Status Check:"
    active_processes=$(ps aux | grep 3proxy | grep -v grep | wc -l)
    total_plans=$(jq length "$PROXY_LOG" 2>/dev/null || echo "0")
    echo "   Active 3proxy processes: $active_processes"
    echo "   Total plans in log: $total_plans"
    
    # Show cleaned plan summary
    echo ""
    echo "📋 Cleaned Plan Summary:"
    jq -r '.[] | "   ✅ \(.plan_id) (\(.username)) - \(.subdomain):\(.local_port) → \(.auth_host):\(.auth_port)"' "$PROXY_LOG"
fi
