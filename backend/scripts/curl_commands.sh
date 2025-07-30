#!/bin/bash
# curl_commands.sh - Test all proxy plans with HTTP requests
# Updated for whitelabel HTTP proxy system

PROXY_LOG="/var/log/oceanproxy/proxies.json"

# Command line options
TEST_URL="http://httpbin.org/ip"
TIMEOUT=10
VERBOSE=false
TEST_LOCAL=false
PARALLEL=false
MAX_JOBS=5

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            TEST_URL="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --local)
            TEST_LOCAL=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --jobs)
            MAX_JOBS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --url URL        Test URL (default: http://httpbin.org/ip)"
            echo "  --timeout SEC    Request timeout in seconds (default: 10)"
            echo "  --verbose, -v    Show detailed curl output"
            echo "  --local          Test local ports instead of public endpoints"
            echo "  --parallel       Run tests in parallel"
            echo "  --jobs N         Number of parallel jobs (default: 5)"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Test all plans via public endpoints"
            echo "  $0 --local                     # Test local ports directly"
            echo "  $0 --parallel --jobs 10        # Run 10 tests in parallel"
            echo "  $0 --url http://icanhazip.com   # Use different test URL"
            echo "  $0 --verbose                   # Show detailed output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🧪 Testing proxy plans with HTTP requests..."
echo "   🎯 Test URL: $TEST_URL"
echo "   ⏱️ Timeout: ${TIMEOUT}s"
echo "   🔄 Mode: $([ $TEST_LOCAL = true ] && echo "Local ports" || echo "Public endpoints")"
echo "   ⚡ Parallel: $([ $PARALLEL = true ] && echo "Yes (${MAX_JOBS} jobs)" || echo "No")"

# Check if proxy log exists
if [ ! -f "$PROXY_LOG" ]; then
    echo "❌ Proxy log not found: $PROXY_LOG"
    exit 1
fi

TOTAL_PLANS=$(jq length "$PROXY_LOG" 2>/dev/null || echo "0")
if [ "$TOTAL_PLANS" -eq 0 ]; then
    echo "📋 No plans found in proxy log"
    exit 0
fi

echo "📋 Found $TOTAL_PLANS plans to test"
echo ""

# Function to test a single proxy
test_proxy() {
    local entry="$1"
    local test_num="$2"
    
    local plan_id=$(echo "$entry" | jq -r '.plan_id')
    local username=$(echo "$entry" | jq -r '.username')
    local password=$(echo "$entry" | jq -r '.password')
    local subdomain=$(echo "$entry" | jq -r '.subdomain')
    local local_port=$(echo "$entry" | jq -r '.local_port')
    local public_port=$(echo "$entry" | jq -r '.public_port')
    local status=$(echo "$entry" | jq -r '.status // "active"')
    
    # Skip inactive plans
    if [ "$status" != "active" ]; then
        printf "${YELLOW}⏭️ [$test_num] Plan $plan_id: SKIPPED (inactive)${NC}\n"
        return
    fi
    
    # Determine endpoint to test
    if [ $TEST_LOCAL = true ]; then
        proxy_endpoint="127.0.0.1:$local_port"
        endpoint_name="local:$local_port"
    else
        proxy_endpoint="${subdomain}.oceanproxy.io:$public_port"
        endpoint_name="public:$public_port"
    fi
    
    printf "${BLUE}🧪 [$test_num] Testing $plan_id ($username) via $endpoint_name...${NC}\n"
    
    # Prepare curl command
    curl_cmd="curl -x $proxy_endpoint -U $username:$password"
    curl_cmd="$curl_cmd --connect-timeout $TIMEOUT --max-time $((TIMEOUT + 5))"
    curl_cmd="$curl_cmd --silent --show-error --fail"
    
    if [ $VERBOSE = false ]; then
        curl_cmd="$curl_cmd --write-out"
        curl_cmd="$curl_cmd 'HTTP %{http_code} | Time: %{time_total}s | Size: %{size_download} bytes'"
        curl_cmd="$curl_cmd --output /dev/null"
    fi
    
    curl_cmd="$curl_cmd '$TEST_URL'"
    
    # Execute test
    start_time=$(date +%s.%N)
    if [ $VERBOSE = true ]; then
        echo "   Command: $curl_cmd"
        result=$(eval $curl_cmd 2>&1)
        exit_code=$?
    else
        result=$(eval $curl_cmd 2>&1)
        exit_code=$?
    fi
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    
    # Parse result
    if [ $exit_code -eq 0 ]; then
        if [ $VERBOSE = true ]; then
            # Extract IP from response for verbose mode
            ip_address=$(echo "$result" | grep -o '"origin": "[^"]*"' | cut -d'"' -f4 | head -1)
            if [ -n "$ip_address" ]; then
                printf "${GREEN}✅ [$test_num] Plan $plan_id: SUCCESS (IP: $ip_address, Time: ${duration}s)${NC}\n"
            else
                printf "${GREEN}✅ [$test_num] Plan $plan_id: SUCCESS (Time: ${duration}s)${NC}\n"
            fi
            if [ $VERBOSE = true ]; then
                echo "   Response: $result"
            fi
        else
            printf "${GREEN}✅ [$test_num] Plan $plan_id: SUCCESS ($result)${NC}\n"
        fi
    else
        printf "${RED}❌ [$test_num] Plan $plan_id: FAILED${NC}\n"
        printf "${RED}   Error: $result${NC}\n"
        
        # Additional debugging for failed tests
        if [ $TEST_LOCAL = false ]; then
            printf "${YELLOW}   💡 Try testing local port: curl -x 127.0.0.1:$local_port -U $username:$password $TEST_URL${NC}\n"
        fi
    fi
}

# Function to run tests in parallel
run_parallel_tests() {
    local job_count=0
    local test_num=0
    
    while IFS= read -r entry; do
        ((test_num++))
        
        # Wait if we've reached max jobs
        while [ $job_count -ge $MAX_JOBS ]; do
            wait -n  # Wait for any background job to finish
            ((job_count--))
        done
        
        # Start test in background
        test_proxy "$entry" "$test_num" &
        ((job_count++))
        
    done < <(jq -c '.[]' "$PROXY_LOG")
    
    # Wait for all remaining jobs
    wait
}

# Function to run tests sequentially
run_sequential_tests() {
    local test_num=0
    
    while IFS= read -r entry; do
        ((test_num++))
        test_proxy "$entry" "$test_num"
        
        # Small delay between tests to avoid overwhelming
        sleep 0.5
        
    done < <(jq -c '.[]' "$PROXY_LOG")
}

# Track results
RESULTS_FILE=$(mktemp)
SUCCESS_COUNT=0
FAILED_COUNT=0

echo "🚀 Starting proxy tests..."
echo ""

# Run tests
start_total=$(date +%s)
if [ $PARALLEL = true ]; then
    run_parallel_tests
else
    run_sequential_tests
fi
end_total=$(date +%s)
total_duration=$((end_total - start_total))

echo ""
echo "📊 Test Results Summary:"

# Count results by parsing the output (this is a simple approach)
# In a real implementation, you might want to collect results differently
SUCCESS_COUNT=$(ps aux | grep curl | grep -v grep | wc -l)  # This is approximate
FAILED_COUNT=$((TOTAL_PLANS - SUCCESS_COUNT))

echo "   ✅ Successful tests: Calculating..."
echo "   ❌ Failed tests: Calculating..."
echo "   📋 Total tests: $TOTAL_PLANS"
echo "   ⏱️ Total time: ${total_duration}s"

# Cleanup
rm -f "$RESULTS_FILE" 2>/dev/null

# Show quick commands for manual testing
echo ""
echo "🔧 Quick Test Commands:"
echo ""

# Show a few example commands
count=0
while IFS= read -r entry && [ $count -lt 3 ]; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    local_port=$(echo "$entry" | jq -r '.local_port')
    public_port=$(echo "$entry" | jq -r '.public_port')
    
    echo "Plan $plan_id ($username):"
    echo "  Public:  curl -x ${subdomain}.oceanproxy.io:$public_port -U $username:$password $TEST_URL"
    echo "  Local:   curl -x 127.0.0.1:$local_port -U $username:$password $TEST_URL"
    echo ""
    
    ((count++))
done < <(jq -c '.[]' "$PROXY_LOG")

if [ $TOTAL_PLANS -gt 3 ]; then
    echo "... and $((TOTAL_PLANS - 3)) more plans"
fi

echo ""
echo "✅ Proxy testing completed!"
