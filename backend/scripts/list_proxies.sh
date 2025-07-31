#!/bin/bash
# list_proxies.sh - Display all current proxies in host:port:user:pass format
# Perfect for sharing with customers or testing

PROXY_LOG="/var/log/oceanproxy/proxies.json"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Command line options
FORMAT="customer"
SHOW_LOCAL=false
SHOW_BOTH=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            SHOW_LOCAL=true
            shift
            ;;
        --both)
            SHOW_BOTH=true
            shift
            ;;
        --raw)
            FORMAT="raw"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --local      Show local endpoints (127.0.0.1:port) instead of public"
            echo "  --both       Show both public and local endpoints"
            echo "  --raw        Raw output without colors or formatting"
            echo "  --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Show public endpoints for customers"
            echo "  $0 --local           # Show local endpoints for debugging"  
            echo "  $0 --both            # Show both public and local"
            echo "  $0 --raw             # Plain text output for scripts"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if proxy log exists
if [ ! -f "$PROXY_LOG" ]; then
    echo "❌ Proxy log not found: $PROXY_LOG"
    exit 1
fi

TOTAL_PLANS=$(jq length "$PROXY_LOG" 2>/dev/null || echo "0")
if [ "$TOTAL_PLANS" -eq 0 ]; then
    echo "📋 No active proxy plans found"
    exit 0
fi

# Function to get public endpoint based on subdomain
get_public_endpoint() {
    local subdomain="$1"
    case "$subdomain" in
        "usa") echo "usa.oceanproxy.io:1337" ;;
        "eu") echo "eu.oceanproxy.io:1338" ;;
        "alpha") echo "alpha.oceanproxy.io:9876" ;;
        "beta") echo "beta.oceanproxy.io:8765" ;;
        "mobile") echo "mobile.oceanproxy.io:7654" ;;
        "unlim") echo "unlim.oceanproxy.io:6543" ;;
        "datacenter") echo "datacenter.oceanproxy.io:1339" ;;
        *) echo "${subdomain}.oceanproxy.io:8080" ;;
    esac
}

# Function to format output based on mode
print_proxy() {
    local host="$1"
    local port="$2"  
    local username="$3"
    local password="$4"
    local label="$5"
    
    if [ "$FORMAT" = "raw" ]; then
        echo "${host}:${port}:${username}:${password}"
    else
        printf "${CYAN}%-25s${NC} ${GREEN}%s${NC}:${YELLOW}%s${NC}:${BLUE}%s${NC}:${BLUE}%s${NC}\n" \
            "$label" "$host" "$port" "$username" "$password"
    fi
}

# Header
if [ "$FORMAT" != "raw" ]; then
    echo ""
    echo "🌊 OceanProxy - Active Proxy Endpoints"
    echo "======================================"
    echo ""
    
    if [ "$SHOW_BOTH" = true ]; then
        echo "📋 Showing both public (customer) and local (debug) endpoints:"
    elif [ "$SHOW_LOCAL" = true ]; then
        echo "🔧 Showing local endpoints (for debugging):"
    else
        echo "🌐 Showing public endpoints (for customers):"
    fi
    echo ""
fi

# Process each proxy plan
while IFS= read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    local_port=$(echo "$entry" | jq -r '.local_port')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    expires_at=$(echo "$entry" | jq -r '.expires_at')
    
    # Skip invalid entries
    if [ "$plan_id" = "null" ] || [ "$username" = "null" ]; then
        continue
    fi
    
    # Get public endpoint
    public_endpoint=$(get_public_endpoint "$subdomain")
    public_host=$(echo "$public_endpoint" | cut -d':' -f1)
    public_port=$(echo "$public_endpoint" | cut -d':' -f2)
    
    # Show endpoints based on options
    if [ "$SHOW_BOTH" = true ]; then
        print_proxy "$public_host" "$public_port" "$username" "$password" "Public ($subdomain)"
        print_proxy "127.0.0.1" "$local_port" "$username" "$password" "Local ($subdomain)"
        if [ "$FORMAT" != "raw" ]; then
            echo ""
        fi
    elif [ "$SHOW_LOCAL" = true ]; then
        print_proxy "127.0.0.1" "$local_port" "$username" "$password" "Local ($subdomain)"
    else
        print_proxy "$public_host" "$public_port" "$username" "$password" "Public ($subdomain)"
    fi
    
done < <(jq -c '.[] | select(.plan_id != null and .username != null)' "$PROXY_LOG" | sort)

# Footer
if [ "$FORMAT" != "raw" ]; then
    echo ""
    echo "📊 Total active proxies: $TOTAL_PLANS"
    echo ""
    echo "💡 Usage examples:"
    echo "   curl -x usa.oceanproxy.io:1337 -U username:password http://httpbin.org/ip"
    echo "   curl --proxy http://username:password@usa.oceanproxy.io:1337 http://example.com"
    echo ""
    echo "🔧 Test all proxies: ./curl_commands.sh"
    echo "❤️ Check health: ./ensure_proxies.sh"
    echo ""
fi
