#!/bin/bash

################################################################################
# Plex Mount Monitor Script
# 
# This script monitors bind mounts in a Proxmox CT and automatically remounts
# them if they fail. It dynamically detects all bind mounts (mp0, mp1, mp2, etc.)
# and monitors them continuously.
#
# Usage: ./plex-mount-monitor.sh [options]
# Options:
#   -i, --interval SECONDS    Check interval in seconds (default: 60)
#   -l, --log FILE           Log file path (default: /var/log/plex-mount-monitor.log)
#   -v, --verbose            Enable verbose logging
#   -h, --help               Show this help message
################################################################################

# Default configuration
CHECK_INTERVAL=60
LOG_FILE="/var/log/plex-mount-monitor.log"
VERBOSE=0
CT_ID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

# Print usage information
usage() {
    cat << EOF
Plex Mount Monitor Script

Usage: $0 [options]

Options:
    -i, --interval SECONDS    Check interval in seconds (default: 60)
    -l, --log FILE           Log file path (default: /var/log/plex-mount-monitor.log)
    -v, --verbose            Enable verbose logging
    -h, --help               Show this help message

Description:
    This script monitors bind mounts in a Proxmox CT and automatically
    remounts them if they fail. It dynamically detects all bind mounts
    (mp0, mp1, mp2, etc.) and monitors them continuously.

EOF
    exit 0
}

# Log message with timestamp
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Verbose log (only if verbose mode is enabled)
log_verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        log_message "DEBUG" "$@"
    fi
}

# Get the CT ID from inside the container
get_ct_id() {
    # Try to get CT ID from /proc/self/cgroup
    if [ -f /proc/self/cgroup ]; then
        CT_ID=$(grep -oP '(?<=lxc/)\d+' /proc/self/cgroup 2>/dev/null | head -1)
    fi
    
    # Alternative method: check hostname or /etc/hostname
    if [ -z "$CT_ID" ]; then
        CT_ID=$(hostname | grep -oP '\d+' | head -1)
    fi
    
    log_verbose "Detected CT ID: ${CT_ID:-unknown}"
}

# Detect all bind mounts from /proc/mounts
detect_bind_mounts() {
    local mounts=()
    
    # Read /proc/mounts and find bind mounts
    # Bind mounts typically have the same device as their source
    while IFS= read -r line; do
        # Skip common system mounts
        if echo "$line" | grep -qE '^(proc|sysfs|devtmpfs|tmpfs|cgroup|mqueue|hugetlbfs|debugfs|tracefs|fusectl|configfs|securityfs|pstore|bpf|autofs)'; then
            continue
        fi
        
        # Extract mount point (second field)
        mount_point=$(echo "$line" | awk '{print $2}')
        
        # Skip root and common system directories
        if [[ "$mount_point" == "/" ]] || \
           [[ "$mount_point" == "/dev" ]] || \
           [[ "$mount_point" == "/dev/pts" ]] || \
           [[ "$mount_point" == "/sys" ]] || \
           [[ "$mount_point" == "/proc" ]] || \
           [[ "$mount_point" == "/run" ]] || \
           [[ "$mount_point" == "/boot"* ]] || \
           [[ "$mount_point" == "/snap"* ]]; then
            continue
        fi
        
        # Check if it's a bind mount (contains 'bind' in options or is a directory mounted from host)
        if echo "$line" | grep -qE 'bind|rbind'; then
            mounts+=("$mount_point")
            log_verbose "Detected bind mount: $mount_point"
        fi
    done < /proc/mounts
    
    # If no bind mounts detected via /proc/mounts, try to detect from common locations
    if [ ${#mounts[@]} -eq 0 ]; then
        log_verbose "No bind mounts detected from /proc/mounts, checking common locations..."
        
        # Check for common Plex mount locations
        for dir in /mnt/mp* /media/mp* /mnt/* /media/*; do
            if [ -d "$dir" ] && mountpoint -q "$dir" 2>/dev/null; then
                mounts+=("$dir")
                log_verbose "Found mounted directory: $dir"
            fi
        done
    fi
    
    # Return the array
    printf '%s\n' "${mounts[@]}"
}

# Check if a mount point is accessible
check_mount() {
    local mount_point="$1"
    
    # Check if mount point exists
    if [ ! -d "$mount_point" ]; then
        log_verbose "Mount point does not exist: $mount_point"
        return 1
    fi
    
    # Check if it's actually mounted
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        log_verbose "Not a mount point: $mount_point"
        return 1
    fi
    
    # Try to access the mount point (test read access)
    if ! timeout 5 ls "$mount_point" >/dev/null 2>&1; then
        log_verbose "Cannot access mount point: $mount_point"
        return 1
    fi
    
    return 0
}

# Attempt to remount a failed mount
remount_mount() {
    local mount_point="$1"
    
    log_message "WARN" "Mount point $mount_point is not accessible, attempting to remount..."
    
    # Try to unmount first (if it's in a bad state)
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_verbose "Unmounting $mount_point..."
        if ! umount "$mount_point" 2>/dev/null; then
            log_verbose "Normal unmount failed, trying lazy unmount..."
            umount -l "$mount_point" 2>/dev/null
        fi
        sleep 2
    fi
    
    # Get the mount information from /etc/fstab or try to remount
    if grep -q "$mount_point" /etc/fstab 2>/dev/null; then
        log_verbose "Found entry in /etc/fstab, attempting mount..."
        if mount "$mount_point" 2>&1 | tee -a "$LOG_FILE"; then
            log_message "INFO" "Successfully remounted $mount_point"
            return 0
        else
            log_message "ERROR" "Failed to remount $mount_point from /etc/fstab"
            return 1
        fi
    else
        log_message "WARN" "No /etc/fstab entry found for $mount_point"
        log_message "INFO" "You may need to manually configure this mount in /etc/fstab"
        return 1
    fi
}

# Main monitoring loop
monitor_mounts() {
    log_message "INFO" "Starting Plex Mount Monitor..."
    log_message "INFO" "Check interval: ${CHECK_INTERVAL}s"
    log_message "INFO" "Log file: $LOG_FILE"
    
    get_ct_id
    
    # Track mount points across iterations
    declare -A known_mounts
    
    while true; do
        # Detect current bind mounts
        mapfile -t current_mounts < <(detect_bind_mounts)
        
        # Check for new mounts
        for mount_point in "${current_mounts[@]}"; do
            if [ -z "$mount_point" ]; then
                continue
            fi
            
            if [ -z "${known_mounts[$mount_point]}" ]; then
                log_message "INFO" "New bind mount detected: $mount_point"
                known_mounts[$mount_point]=1
            fi
        done
        
        # Check each known mount
        for mount_point in "${!known_mounts[@]}"; do
            if ! check_mount "$mount_point"; then
                log_message "ERROR" "Mount check failed for: $mount_point"
                
                # Attempt to remount
                if remount_mount "$mount_point"; then
                    # Verify the remount was successful
                    sleep 2
                    if check_mount "$mount_point"; then
                        log_message "INFO" "Mount verification successful: $mount_point"
                    else
                        log_message "ERROR" "Mount verification failed after remount: $mount_point"
                    fi
                fi
            else
                log_verbose "Mount OK: $mount_point"
            fi
        done
        
        # Remove mounts that no longer exist
        for mount_point in "${!known_mounts[@]}"; do
            if [ ! -d "$mount_point" ]; then
                log_message "INFO" "Mount point removed: $mount_point"
                unset known_mounts[$mount_point]
            fi
        done
        
        # Wait for next check
        sleep "$CHECK_INTERVAL"
    done
}

################################################################################
# Parse command line arguments
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

################################################################################
# Main execution
################################################################################

# Ensure log directory exists
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        echo "Error: Cannot create log directory: $LOG_DIR"
        exit 1
    }
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Warning: This script should be run as root for full functionality"
fi

# Start monitoring
monitor_mounts