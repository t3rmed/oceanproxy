#!/bin/bash
# ping_proxies_improved.sh - Test proxy latency with multiple samples and averages
# Tests both your endpoints and upstream providers with 10 requests per endpoint

PROXY_LOG="/var/log/oceanproxy/proxies.json"
REQUESTS_PER_TEST=10

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Command line options
TEST_UPSTREAM=false
TEST_LOCAL=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --upstream)
            TEST_UPSTREAM=true
            shift
            ;;
        --local)
            TEST_LOCAL=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --requests|-r)
            REQUESTS_PER_TEST="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --upstream        Test ping to upstream providers (pr-us.proxies.fo, etc.)"
            echo "  --local          Test local ports (127.0.0.1:10000, etc.)"
            echo "  --verbose        Show detailed ping output"
            echo "  --requests N     Number of requests per test (default: 10)"
            echo "  --help           Show this help message"
            echo ""
            echo "Default: Tests your public endpoints (usa.oceanproxy.io, etc.)"
            echo ""
            echo "Examples:"
            echo "  $0                       # Test public endpoints (10 requests each)"
            echo "  $0 --upstream            # Test upstream providers"
            echo "  $0 --local               # Test local ports"
            echo "  $0 --requests 20         # 20 requests per test"
            echo "  $0 --verbose             # Detailed output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to ping a host multiple times
ping_host() {
    local host="$1"
    local label="$2"
    local port="$3"
    
    if [ "$VERBOSE" = true ]; then
        echo "🔍 Testing: $label ($host:$port)"
        ping -c "$REQUESTS_PER_TEST" "$host"
        echo ""
    else
        # Multiple ping test for average
        local result=$(ping -c "$REQUESTS_PER_TEST" -W 3 "$host" 2>/dev/null | tail -1)
        if echo "$result" | grep -q "min/avg/max"; then
            local avg_time=$(echo "$result" | awk -F'/' '{print $5}')
            local min_time=$(echo "$result" | awk -F'/' '{print $4}')
            local max_time=$(echo "$result" | awk -F'/' '{print $6}')
            local status="✅"
            local color="$GREEN"
            
            # Color code based on latency
            if (( $(echo "$avg_time > 200" | bc -l) )); then
                color="$RED"
                status="🔴"
            elif (( $(echo "$avg_time > 100" | bc -l) )); then
                color="$YELLOW" 
                status="🟡"
            fi
            
            printf "${color}%-8s${NC} %-25s ${color}%6.1fms${NC} ${GRAY}(min:%4.1f max:%4.1f)${NC}\n" "$status" "$label ($host:$port)" "$avg_time" "$min_time" "$max_time"
        else
            printf "${RED}%-8s${NC} %-25s ${RED}%6s${NC}\n" "❌" "$label ($host:$port)" "FAIL"
        fi
    fi
}

# Function to test HTTP response time via proxy with multiple requests
test_proxy_latency() {
    local host="$1"
    local port="$2"
    local username="$3"
    local password="$4"
    local label="$5"
    
    echo -n "Testing $label... "
    
    local total_time=0
    local successful_requests=0
    local min_time=999999
    local max_time=0
    local times=()
    
    for i in $(seq 1 "$REQUESTS_PER_TEST"); do
        local start_time=$(date +%s.%N)
        local result=$(curl -x "$host:$port" -U "$username:$password" \
                           --connect-timeout 10 --max-time 15 \
                           --silent --write-out "%{time_total}" \
                           --output /dev/null \
                           "http://httpbin.org/ip" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            local latency_ms=$(echo "$result * 1000" | bc)
            times+=("$latency_ms")
            total_time=$(echo "$total_time + $latency_ms" | bc)
            successful_requests=$((successful_requests + 1))
            
            # Track min/max
            if (( $(echo "$latency_ms < $min_time" | bc -l) )); then
                min_time="$latency_ms"
            fi
            if (( $(echo "$latency_ms > $max_time" | bc -l) )); then
                max_time="$latency_ms"
            fi
        fi
        
        # Progress indicator
        echo -n "."
    done
    
    echo "" # New line after progress dots
    
    if [ "$successful_requests" -gt 0 ]; then
        local avg_time=$(echo "scale=1; $total_time / $successful_requests" | bc)
        local success_rate=$(echo "scale=1; $successful_requests * 100 / $REQUESTS_PER_TEST" | bc)
        local status="✅"
        local color="$GREEN"
        
        # Color code based on response time
        if (( $(echo "$avg_time > 3000" | bc -l) )); then
            color="$RED"
            status="🔴"
        elif (( $(echo "$avg_time > 1000" | bc -l) )); then
            color="$YELLOW"
            status="🟡"
        fi
        
        # Calculate standard deviation for consistency
        if [ "$successful_requests" -gt 1 ]; then
            local sum_squares=0
            for time in "${times[@]}"; do
                local diff=$(echo "$time - $avg_time" | bc)
                local square=$(echo "$diff * $diff" | bc)
                sum_squares=$(echo "$sum_squares + $square" | bc)
            done
            local variance=$(echo "scale=2; $sum_squares / $successful_requests" | bc)
            local std_dev=$(echo "scale=1; sqrt($variance)" | bc)
            
            printf "${color}%-8s${NC} %-25s ${color}%7.0fms${NC} ${GRAY}(min:%4.0f max:%4.0f ±%.0f) %s%%${NC}\n" \
                   "$status" "$label ($host:$port)" "$avg_time" "$min_time" "$max_time" "$std_dev" "$success_rate"
        else
            printf "${color}%-8s${NC} %-25s ${color}%7.0fms${NC} ${GRAY}(min:%4.0f max:%4.0f) %s%%${NC}\n" \
                   "$status" "$label ($host:$port)" "$avg_time" "$min_time" "$max_time" "$success_rate"
        fi
    else
        printf "${RED}%-8s${NC} %-25s ${RED}%7s${NC} ${GRAY}(0/%d successful)${NC}\n" \
               "❌" "$label ($host:$port)" "FAIL" "$REQUESTS_PER_TEST"
    fi
}

echo ""
echo "🏓 OceanProxy - Advanced Latency Test"
echo "====================================="
echo "📊 Testing with $REQUESTS_PER_TEST requests per endpoint for accurate averages"
echo ""

# Check if bc is installed for calculations
if ! command -v bc &> /dev/null; then
    echo "📦 Installing bc for calculations..."
    apt-get update && apt-get install -y bc >/dev/null 2>&1
fi

if [ "$TEST_UPSTREAM" = true ]; then
    echo "🌐 Testing upstream providers:"
    echo ""
    printf "%-9s %-30s %-12s %s\n" "Status" "Provider" "Avg Latency" "Range"
    echo "─────────────────────────────────────────────────────────────────────"
    
    # Test unique upstream providers
    declare -A tested_upstreams
    while IFS= read -r entry; do
        auth_host=$(echo "$entry" | jq -r '.auth_host')
        auth_port=$(echo "$entry" | jq -r '.auth_port')
        
        if [ "$auth_host" != "null" ] && [ -z "${tested_upstreams[$auth_host]}" ]; then
            tested_upstreams[$auth_host]=1
            ping_host "$auth_host" "$auth_host" "$auth_port"
        fi
    done < <(jq -c '.[]' "$PROXY_LOG" 2>/dev/null)

elif [ "$TEST_LOCAL" = true ]; then
    echo "🔧 Testing local proxy instances (HTTP response time):"
    echo ""
    printf "%-9s %-30s %-12s %s\n" "Status" "Local Endpoint" "Avg Response" "Consistency & Success"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    while IFS= read -r entry; do
        username=$(echo "$entry" | jq -r '.username')
        password=$(echo "$entry" | jq -r '.password')
        local_port=$(echo "$entry" | jq -r '.local_port')
        subdomain=$(echo "$entry" | jq -r '.subdomain')
        
        if [ "$username" != "null" ]; then
            test_proxy_latency "127.0.0.1" "$local_port" "$username" "$password" "Local $subdomain"
        fi
    done < <(jq -c '.[]' "$PROXY_LOG" 2>/dev/null)

else
    echo "🌐 Testing public proxy endpoints (HTTP response time):"
    echo ""
    printf "%-9s %-30s %-12s %s\n" "Status" "Public Endpoint" "Avg Response" "Consistency & Success"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    # Function to get public endpoint
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
    
    while IFS= read -r entry; do
        username=$(echo "$entry" | jq -r '.username')
        password=$(echo "$entry" | jq -r '.password')
        subdomain=$(echo "$entry" | jq -r '.subdomain')
        
        if [ "$username" != "null" ]; then
            endpoint=$(get_public_endpoint "$subdomain")
            host=$(echo "$endpoint" | cut -d':' -f1)
            port=$(echo "$endpoint" | cut -d':' -f2)
            
            test_proxy_latency "$host" "$port" "$username" "$password" "Public $subdomain"
        fi
    done < <(jq -c '.[]' "$PROXY_LOG" 2>/dev/null)
fi

echo ""
echo "📊 Performance Guide:"
echo "   🟢 ✅  <100ms   - Excellent"
echo "   🟡 🟡  100-200ms - Good" 
echo "   🔴 🔴  >200ms   - Slow"
echo "   ❌     Failed    - Connection issues"
echo ""
echo "📈 Reading the stats:"
echo "   • Avg Response: Average time across $REQUESTS_PER_TEST requests"
echo "   • min/max: Fastest and slowest individual request"
echo "   • ±X: Standard deviation (lower = more consistent)"
echo "   • %: Success rate (should be 100%)"
echo ""

if [ "$TEST_UPSTREAM" = false ]; then
    echo "💡 Additional tests:"
    echo "   • Test upstream providers: $0 --upstream"
    echo "   • Test local instances: $0 --local"  
    echo "   • More requests: $0 --requests 20"
    echo "   • Verbose output: $0 --verbose"
    echo ""
fi
