#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check for required parameters
if [ $# -lt 4 ]; then
    echo -e "${BOLD}${CYAN}=== API MONITORING TOOL ===${NC}"
    echo -e "${WHITE}Usage: $0 <API_URL> <total_time_minutes> <interval_seconds> <threshold_ms> [timeout_seconds] [analysis_mode]${NC}"
    echo -e "${WHITE}Example: $0 https://api.example.com/endpoint 30 300 1500 5${NC}"
    echo -e "${WHITE}Analysis modes: 0 - delays only, 1 - errors and delays, 2 - full analysis${NC}"
    echo -e "${WHITE}Available colors: ${GREEN}Green${NC}, ${RED}Red${NC}, ${YELLOW}Yellow${NC}, ${BLUE}Blue${NC}"
    exit 1
fi

# Parameters
API_URL="$1"
TOTAL_TIME_MINUTES="$2"
INTERVAL_SEC="$3"
THRESHOLD_MS="$4"
TIMEOUT_SEC="${5:-5}"  # Default 5 seconds
ANALYSIS_MODE="${6:-1}"  # Default analysis of errors and delays

# Timeout limitation not exceeding interval between iterations
if [ "$TIMEOUT_SEC" -gt "$INTERVAL_SEC" ]; then
    TIMEOUT_SEC="$INTERVAL_SEC"
fi

TOTAL_TIME_SEC=$((TOTAL_TIME_MINUTES * 60))
MAX_ITERATIONS=$((TOTAL_TIME_SEC / INTERVAL_SEC))

# Generate log file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOGS_DIR"

# Create unique log file name
API_NAME=$(echo "$API_URL" | tr -d 'https://:/')
LOG_FILE_NAME="api_monitor_${API_NAME}_$(date +%Y%m%d_%H%M%S).log"
LOG_FILE="$LOGS_DIR/$LOG_FILE_NAME"

# Variables for counting
TOTAL_CHECKS=0
SLOW_RESPONSES=0
ERROR_RESPONSES=0
TIMEOUT_RESPONSES=0
HTTP_ERROR_RESPONSES=0
SUCCESS_RESPONSES=0
MAX_LATENCY=0
MIN_LATENCY=0
MAX_LATENCY_TIME=""
MIN_LATENCY_TIME=""

# Variables to store last errors
LAST_ERROR_CODE=""
LAST_ERROR_TIME=""
LAST_TIMEOUT_TIME=""


handle_timestamp() {
    local message="$1"
    local with_timestamp="${2:-false}"
    
    if [ "$with_timestamp" = "true" ]; then
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] $message"
    else
        echo "$message"
    fi
}

# Function for logging to file only
log_to_file() {
    local message="$1"
    local with_timestamp="${2:-false}"
    
    local formatted_message
    formatted_message=$(handle_timestamp "$message" "$with_timestamp")
    echo "$formatted_message" >> "$LOG_FILE" 2>/dev/null
}

# Function for logging to console only (with colors)
log_to_console() {
    local message="$1"
    local with_timestamp="${2:-false}"
    
    local formatted_message
    formatted_message=$(handle_timestamp "$message" "$with_timestamp")
    echo -e "${formatted_message}" 2>/dev/null
}

# Function for logging to both console and file with colors (optimized)
log_to_both() {
    local message="$1"
    local with_timestamp="${2:-false}"
    
    # Log to console (with colors)
    local console_message
    console_message=$(handle_timestamp "$message" "$with_timestamp")
    echo -e "${console_message}" 2>/dev/null
    
    # Log to file (without colors)
    local file_message
    file_message=$(handle_timestamp "$message" "$with_timestamp")
    echo "$file_message" >> "$LOG_FILE" 2>/dev/null
}

# Function for displaying progress in real-time with animation
show_progress() {
    local current="$1"
    local max="$2"
    local percentage=$((current * 100 / max))
    
    # Create progress animation
    local bar_length=30
    local filled_length=$((percentage * bar_length / 100))
    local bar=""
    
    for ((i=0; i<bar_length; i++)); do
        if [ $i -lt $filled_length ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
    done
    
    echo -ne "\r${BOLD}${CYAN}📊 Progress:${NC} ${bar} ${WHITE}${percentage}%${NC} (${current}/${max})  "
}

# Function for displaying status with colors
show_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success")
            echo -e "${GREEN}✅ ${message}${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  ${message}${NC}"
            ;;
        "error")
            echo -e "${RED}❌ ${message}${NC}"
            ;;
        "info")
            echo -e "${BLUE}ℹ️  ${message}${NC}"
            ;;
        *)
            echo -e "${WHITE}${message}${NC}"
            ;;
    esac
}

# Function for displaying statistics in table format
show_stats_table() {
    local title="$1"
    local data=("${@:2}")
    
    echo -e "${BOLD}${PURPLE}=== ${title} ===${NC}"
    printf "${WHITE}%-20s | %-15s | %-15s${NC}\n" "Category" "Value" "Percentage"
    echo -e "${WHITE}────────────────────┼─────────────────┼─────────────────${NC}"
    
    for i in "${!data[@]}"; do
        if [ $((i % 3)) -eq 0 ]; then
            local category="${data[i]}"
            local value="${data[i+1]}"
            local percentage="${data[i+2]}"
            printf "${WHITE}%-20s | %-15s | %-15s${NC}\n" "$category" "$value" "$percentage%"
        fi
    done
    echo -e "${WHITE}────────────────────┼─────────────────┼─────────────────${NC}"
}

# Function for checking API availability before starting
check_api_availability() {
    local check_url="$1"
    local check_timeout="${2:-5}"
    
    show_status "info" "Checking API availability..."
    
    # Try making one test request
    local test_response=$(curl -s --max-time "$check_timeout" -w "%{http_code}" -o /dev/null "$check_url")
    
    if [ -z "$test_response" ]; then
        show_status "error" "Cannot reach API endpoint"
        return 1
    fi
    
    if [ "$test_response" -lt 200 ] || [ "$test_response" -ge 400 ]; then
        show_status "warning" "API returned HTTP code $test_response"
    else
        show_status "success" "API is available"
    fi
    
    return 0
}

# Function for displaying header
show_header() {
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}                    API MONITORING TOOL                                       ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} URL: ${API_URL} ${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Duration: ${TOTAL_TIME_MINUTES} minutes (${TOTAL_TIME_SEC} seconds) ${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Interval: ${INTERVAL_SEC} seconds ${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Delay threshold: ${THRESHOLD_MS}ms ${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Timeout: ${TIMEOUT_SEC} seconds ${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Analysis mode: ${ANALYSIS_MODE} ${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Log file: ${LOG_FILE_NAME} ${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Function for displaying current status
show_current_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "slow")
            echo -e "${YELLOW}⏱️  SLOW RESPONSE:${NC} ${WHITE}$message${NC}"
            ;;
        "timeout")
            echo -e "${RED}⏰ TIMEOUT:${NC} ${WHITE}$message${NC}"
            ;;
        "http_error")
            echo -e "${RED}❌ HTTP ERROR:${NC} ${WHITE}$message${NC}"
            ;;
        "connection_error")
            echo -e "${RED}🔌 CONNECTION ERROR:${NC} ${WHITE}$message${NC}"
            ;;
        "success")
            # Log successful requests to file but don't display in console
            log_to_both "SUCCESS - Status: $HTTP_CODE, Time: ${RESPONSE_TIME_MS}ms" "true"
            return 0
            ;;
        *)
            echo -e "${BLUE}ℹ️  ${message}${NC}"
            ;;
    esac
}

# Start working
show_header

log_to_file "Starting API monitoring..." "true"
log_to_file "Log file: $LOG_FILE" "true"

# Check API availability
if ! check_api_availability "$API_URL" "$TIMEOUT_SEC"; then
    show_status "error" "Stopping monitoring due to API unavailability"
    exit 1
fi

echo -e "${BOLD}${CYAN}───────────────────────────────────────────────────────────────────────────────${NC}"
show_status "info" "Starting monitoring..."

# Start time
START_TIME=$(date +%s)

# Main monitoring loop
while true; do
    # Check if total time limit is exceeded
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED_TIME -ge $TOTAL_TIME_SEC ]; then
        break
    fi
    
    START=$(date +%s%N)
    
    # Get status and response time with timeout
    RESPONSE=$(curl -s --max-time "$TIMEOUT_SEC" -w "%{http_code} %{time_total}" -o /dev/null "$API_URL")
    
    END=$(date +%s%N)
    
    # Correct calculation of time in milliseconds
    ELAPSED_MS=$(awk "BEGIN {printf \"%.0f\", ($END - $START) / 1000000}")
    
    # Increase check counter
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # Process request result
    if [ -z "$RESPONSE" ]; then
        # Connection error or timeout
        if [ $ELAPSED_MS -gt $TIMEOUT_SEC ]; then
            show_current_status "timeout" "URL: $API_URL, Time: ${ELAPSED_MS}ms"
            TIMEOUT_RESPONSES=$((TIMEOUT_RESPONSES + 1))
            LAST_TIMEOUT_TIME="$(date "+%Y-%m-%d %H:%M:%S")"
            log_to_file "TIMEOUT ERROR - URL: $API_URL, Time: ${ELAPSED_MS}ms" "true"
        else
            show_current_status "connection_error" "URL: $API_URL, Time: ${ELAPSED_MS}ms"
            ERROR_RESPONSES=$((ERROR_RESPONSES + 1))
            log_to_file "CONNECTION ERROR - URL: $API_URL, Time: ${ELAPSED_MS}ms" "true"
        fi
    else
        # Got response from server
        HTTP_CODE=$(echo "$RESPONSE" | awk '{print $1}')
        RESPONSE_TIME_MS=$(echo "$RESPONSE" | awk '{print int($2 * 1000)}')
        
        # Check HTTP codes
        if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 400 ]; then
            # HTTP errors
            show_current_status "http_error" "Status: $HTTP_CODE, Time: ${RESPONSE_TIME_MS}ms"
            HTTP_ERROR_RESPONSES=$((HTTP_ERROR_RESPONSES + 1))
            LAST_ERROR_CODE="$HTTP_CODE"
            LAST_ERROR_TIME="$(date "+%Y-%m-%d %H:%M:%S")"
            log_to_file "HTTP ERROR - Status: $HTTP_CODE, Time: ${RESPONSE_TIME_MS}ms" "true"
        else
            # Successful response
            SUCCESS_RESPONSES=$((SUCCESS_RESPONSES + 1))
            
            # Check delay threshold
            if [ $RESPONSE_TIME_MS -gt $THRESHOLD_MS ]; then
                show_current_status "slow" "Status: $HTTP_CODE, Time: ${RESPONSE_TIME_MS}ms"
                SLOW_RESPONSES=$((SLOW_RESPONSES + 1))
                log_to_file "SLOW RESPONSE - Status: $HTTP_CODE, Time: ${RESPONSE_TIME_MS}ms" "true"
            #else
                # Log successful requests to file but don't display in console
                #log_to_both "SUCCESS - Status: $HTTP_CODE, Time: ${RESPONSE_TIME_MS}ms" "true"
            fi
            
            # Update latency statistics
            if [ $TOTAL_CHECKS -eq 1 ]; then
                # For first check set initial values
                MAX_LATENCY=$RESPONSE_TIME_MS
                MIN_LATENCY=$RESPONSE_TIME_MS
                MAX_LATENCY_TIME="$(date "+%Y-%m-%d %H:%M:%S")"
                MIN_LATENCY_TIME="$(date "+%Y-%m-%d %H:%M:%S")"
            else
                # Update maximum latency
                if [ $RESPONSE_TIME_MS -gt $MAX_LATENCY ]; then
                    MAX_LATENCY=$RESPONSE_TIME_MS
                    MAX_LATENCY_TIME="$(date "+%Y-%m-%d %H:%M:%S")"
                fi
                
                # Update minimum latency
                if [ $RESPONSE_TIME_MS -lt $MIN_LATENCY ]; then
                    MIN_LATENCY=$RESPONSE_TIME_MS
                    MIN_LATENCY_TIME="$(date "+%Y-%m-%d %H:%M:%S")"
                fi
            fi
        fi
    fi
    
    # Display progress in real-time
    show_progress "$TOTAL_CHECKS" "$MAX_ITERATIONS"
    
    sleep $INTERVAL_SEC
done

# Finish progress display
echo -e "\n"

# Display statistics
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${WHITE}                     MONITORING STATISTICS                                    ${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"

# Calculate percentages
SUCCESS_RATE=0
SLOW_RATE=0
ERROR_RATE=0

if [ $TOTAL_CHECKS -gt 0 ]; then
    SUCCESS_RATE=$((SUCCESS_RESPONSES * 100 / TOTAL_CHECKS))
    SLOW_RATE=$((SLOW_RESPONSES * 100 / TOTAL_CHECKS))
    ERROR_RATE=$((ERROR_RESPONSES * 100 / TOTAL_CHECKS))
fi

# Main metrics table
echo -e "${BOLD}${CYAN}║${WHITE} Main metrics:${NC}"
echo -e "${BOLD}${CYAN}║${WHITE} ──────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}║${WHITE} Total checks:${NC} ${WHITE}$TOTAL_CHECKS${NC}"
echo -e "${BOLD}${CYAN}║${WHITE} Successful:${NC} ${GREEN}$SUCCESS_RESPONSES ($SUCCESS_RATE%)${NC}"
echo -e "${BOLD}${CYAN}║${WHITE} Slow:${NC} ${YELLOW}$SLOW_RESPONSES ($SLOW_RATE%)${NC}"
echo -e "${BOLD}${CYAN}║${WHITE} Errors:${NC} ${RED}$ERROR_RESPONSES ($ERROR_RATE%)${NC}"
echo -e "${BOLD}${CYAN}║${WHITE} HTTP errors:${NC} ${RED}$HTTP_ERROR_RESPONSES${NC}"
echo -e "${BOLD}${CYAN}║${WHITE} Timeouts:${NC} ${RED}$TIMEOUT_RESPONSES${NC}"

# Additional information
if [ $TOTAL_CHECKS -gt 0 ]; then
    echo -e "${BOLD}${CYAN}║${WHITE} ──────────────────────────────────────────────${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Latency:${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Minimum time:${NC} ${WHITE}${MIN_LATENCY}ms${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE} Maximum time:${NC} ${WHITE}${MAX_LATENCY}ms${NC}"
    
    if [ -n "$LAST_ERROR_CODE" ]; then
        echo -e "${BOLD}${CYAN}║${WHITE} Last HTTP error:${NC} ${RED}$LAST_ERROR_CODE${NC}"
    fi
    
    if [ -n "$LAST_TIMEOUT_TIME" ]; then
        echo -e "${BOLD}${CYAN}║${WHITE} Last timeout:${NC} ${RED}$LAST_TIMEOUT_TIME${NC}"
    fi
fi

echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"

# Additional information about analysis mode
echo -e "${BOLD}${CYAN}┌───────────────────────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}│${WHITE} Analysis mode:${NC}"
case $ANALYSIS_MODE in
    0)
        echo -e "${BOLD}${CYAN}│${WHITE} Delays only${NC}"
        ;;
    1)
        echo -e "${BOLD}${CYAN}│${WHITE} Errors and delays${NC}"
        ;;
    2)
        echo -e "${BOLD}${CYAN}│${WHITE} Full analysis including response codes${NC}"
        ;;
    *)
        echo -e "${BOLD}${CYAN}│${WHITE} Unknown mode (default errors and delays)${NC}"
        ;;
esac
echo -e "${BOLD}${CYAN}└───────────────────────────────────────────────────────────────────────────────${NC}"

log_to_file "----------------------------------------"
log_to_file "MONITORING COMPLETED" "true"
log_to_file "Total checks performed: $TOTAL_CHECKS"

# Detailed summary in log file
log_to_file "MONITORING SUMMARY"
log_to_file "Total checks performed: $TOTAL_CHECKS"
log_to_file "Successful responses: $SUCCESS_RESPONSES ($SUCCESS_RATE%)"
log_to_file "Slow responses (> $THRESHOLD_MS ms): $SLOW_RESPONSES ($SLOW_RATE%)"
log_to_file "Error responses (connection issues): $ERROR_RESPONSES ($ERROR_RATE%)"
log_to_file "HTTP error responses: $HTTP_ERROR_RESPONSES"
log_to_file "Timeout responses: $TIMEOUT_RESPONSES"

# Output minimum and maximum latency to file
if [ $TOTAL_CHECKS -gt 0 ]; then
    log_to_file "Minimum response time: ${MIN_LATENCY}ms"
    log_to_file "Maximum response time: ${MAX_LATENCY}ms"
    log_to_file "Time of maximum response: $MAX_LATENCY_TIME"
    
    if [ -n "$LAST_ERROR_CODE" ]; then
        log_to_file "Last HTTP error code: $LAST_ERROR_CODE at $LAST_ERROR_TIME"
    fi
    
    if [ -n "$LAST_TIMEOUT_TIME" ]; then
        log_to_file "Last timeout occurred at: $LAST_TIMEOUT_TIME"
    fi
fi

# Finish working
show_status "info" "Monitoring completed"
log_to_file "Monitor finished at: $(date)"

# Add empty line for readability
echo ""
