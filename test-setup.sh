#!/bin/bash

################################################################################
# Plex Mount Monitor - Setup Test Script
#
# This script validates your setup and helps diagnose issues
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓${NC} $*"
}

print_error() {
    echo -e "${RED}✗${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

print_header "Plex Mount Monitor - Setup Validation"

# Test 1: Check if running in CT
print_info "Checking if running in Proxmox CT..."
if [ -f /proc/self/cgroup ] && grep -q "lxc" /proc/self/cgroup 2>/dev/null; then
    print_success "Running in Proxmox CT"
    ((TESTS_PASSED++))
else
    print_warning "May not be running in a Proxmox CT"
    ((TESTS_WARNING++))
fi

# Test 2: Check if running as root
print_info "Checking root privileges..."
if [ "$EUID" -eq 0 ]; then
    print_success "Running as root"
    ((TESTS_PASSED++))
else
    print_error "Not running as root (required for mount operations)"
    ((TESTS_FAILED++))
fi

# Test 3: Check if script is installed
print_info "Checking if monitoring script is installed..."
if [ -f /usr/local/bin/plex-mount-monitor.sh ]; then
    print_success "Script found at /usr/local/bin/plex-mount-monitor.sh"
    ((TESTS_PASSED++))
    
    if [ -x /usr/local/bin/plex-mount-monitor.sh ]; then
        print_success "Script is executable"
        ((TESTS_PASSED++))
    else
        print_error "Script is not executable"
        echo "  Fix: chmod +x /usr/local/bin/plex-mount-monitor.sh"
        ((TESTS_FAILED++))
    fi
else
    print_error "Script not found at /usr/local/bin/plex-mount-monitor.sh"
    echo "  Run: ./install.sh"
    ((TESTS_FAILED++))
fi

# Test 4: Check if service is installed
print_info "Checking if systemd service is installed..."
if [ -f /etc/systemd/system/plex-mount-monitor.service ]; then
    print_success "Service file found"
    ((TESTS_PASSED++))
else
    print_error "Service file not found"
    echo "  Run: ./install.sh"
    ((TESTS_FAILED++))
fi

# Test 5: Check service status
print_info "Checking service status..."
if systemctl is-enabled plex-mount-monitor.service >/dev/null 2>&1; then
    print_success "Service is enabled (will start on boot)"
    ((TESTS_PASSED++))
else
    print_warning "Service is not enabled"
    echo "  Enable: systemctl enable plex-mount-monitor.service"
    ((TESTS_WARNING++))
fi

if systemctl is-active plex-mount-monitor.service >/dev/null 2>&1; then
    print_success "Service is running"
    ((TESTS_PASSED++))
else
    print_warning "Service is not running"
    echo "  Start: systemctl start plex-mount-monitor.service"
    ((TESTS_WARNING++))
fi

# Test 6: Check for bind mounts
print_info "Checking for bind mounts..."
BIND_MOUNTS=$(mount | grep -E "bind|rbind" | grep -v "^proc\|^sys\|^dev\|^tmpfs" | wc -l)
if [ "$BIND_MOUNTS" -gt 0 ]; then
    print_success "Found $BIND_MOUNTS bind mount(s)"
    ((TESTS_PASSED++))
    echo ""
    echo "  Current bind mounts:"
    mount | grep -E "bind|rbind" | grep -v "^proc\|^sys\|^dev\|^tmpfs" | while read -r line; do
        echo "    - $line"
    done
else
    print_warning "No bind mounts detected"
    echo "  This may be normal if mounts haven't been configured yet"
    ((TESTS_WARNING++))
fi

# Test 7: Check /etc/fstab
print_info "Checking /etc/fstab for bind mount entries..."
if grep -q "^[^#]*bind" /etc/fstab 2>/dev/null; then
    FSTAB_ENTRIES=$(grep "^[^#]*bind" /etc/fstab | wc -l)
    print_success "Found $FSTAB_ENTRIES bind mount entry/entries in /etc/fstab"
    ((TESTS_PASSED++))
    echo ""
    echo "  /etc/fstab entries:"
    grep "^[^#]*bind" /etc/fstab | while read -r line; do
        echo "    - $line"
    done
else
    print_error "No bind mount entries in /etc/fstab"
    echo "  The script needs /etc/fstab entries to remount failed mounts"
    echo "  See fstab.example for reference"
    ((TESTS_FAILED++))
fi

# Test 8: Check mount points
print_info "Checking common mount point directories..."
MOUNT_POINTS_FOUND=0
for mp in /mnt/mp0 /mnt/mp1 /mnt/mp2; do
    if [ -d "$mp" ]; then
        if mountpoint -q "$mp" 2>/dev/null; then
            print_success "$mp exists and is mounted"
            ((MOUNT_POINTS_FOUND++))
        else
            print_warning "$mp exists but is not mounted"
        fi
    fi
done

if [ "$MOUNT_POINTS_FOUND" -gt 0 ]; then
    ((TESTS_PASSED++))
else
    print_warning "No standard mount points (mp0, mp1, mp2) found"
    echo "  This may be normal if you use different mount point names"
    ((TESTS_WARNING++))
fi

# Test 9: Check log file
print_info "Checking log file..."
if [ -f /var/log/plex-mount-monitor.log ]; then
    LOG_SIZE=$(stat -f%z /var/log/plex-mount-monitor.log 2>/dev/null || stat -c%s /var/log/plex-mount-monitor.log 2>/dev/null)
    print_success "Log file exists (${LOG_SIZE} bytes)"
    ((TESTS_PASSED++))
    
    if [ "$LOG_SIZE" -gt 0 ]; then
        echo ""
        echo "  Last 5 log entries:"
        tail -5 /var/log/plex-mount-monitor.log | while read -r line; do
            echo "    $line"
        done
    fi
else
    print_warning "Log file not created yet"
    echo "  Will be created when service starts"
    ((TESTS_WARNING++))
fi

# Test 10: Test script syntax
print_info "Checking script syntax..."
if [ -f /usr/local/bin/plex-mount-monitor.sh ]; then
    if bash -n /usr/local/bin/plex-mount-monitor.sh 2>/dev/null; then
        print_success "Script syntax is valid"
        ((TESTS_PASSED++))
    else
        print_error "Script has syntax errors"
        bash -n /usr/local/bin/plex-mount-monitor.sh
        ((TESTS_FAILED++))
    fi
fi

# Summary
print_header "Test Summary"

echo -e "${GREEN}Passed:${NC}   $TESTS_PASSED"
echo -e "${YELLOW}Warnings:${NC} $TESTS_WARNING"
echo -e "${RED}Failed:${NC}   $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -eq 0 ] && [ "$TESTS_WARNING" -eq 0 ]; then
    print_success "All tests passed! Your setup looks good."
    echo ""
    print_info "Next steps:"
    echo "  1. Verify mounts are being monitored: journalctl -u plex-mount-monitor.service -f"
    echo "  2. Check the log file: tail -f /var/log/plex-mount-monitor.log"
elif [ "$TESTS_FAILED" -eq 0 ]; then
    print_warning "Setup is mostly complete, but there are some warnings to review."
    echo ""
    print_info "Review the warnings above and address them if needed."
else
    print_error "There are issues that need to be fixed."
    echo ""
    print_info "Review the errors above and fix them before proceeding."
fi

echo ""
print_info "Useful commands:"
echo "  - View service status:  systemctl status plex-mount-monitor.service"
echo "  - View live logs:       journalctl -u plex-mount-monitor.service -f"
echo "  - View log file:        tail -f /var/log/plex-mount-monitor.log"
echo "  - Restart service:      systemctl restart plex-mount-monitor.service"
echo "  - Test script manually: /usr/local/bin/plex-mount-monitor.sh --verbose"
echo ""

exit $TESTS_FAILED