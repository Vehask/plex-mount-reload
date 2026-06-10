#!/bin/bash

################################################################################
# Plex Mount Monitor - Installation Script
#
# This script installs the Plex Mount Monitor service on your Proxmox CT
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_msg() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

print_success() {
    print_msg "$GREEN" "✓ $*"
}

print_error() {
    print_msg "$RED" "✗ $*"
}

print_warning() {
    print_msg "$YELLOW" "⚠ $*"
}

print_info() {
    print_msg "$BLUE" "ℹ $*"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

print_info "Plex Mount Monitor - Installation Script"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if required files exist
if [ ! -f "$SCRIPT_DIR/plex-mount-monitor.sh" ]; then
    print_error "plex-mount-monitor.sh not found in $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/plex-mount-monitor.service" ]; then
    print_error "plex-mount-monitor.service not found in $SCRIPT_DIR"
    exit 1
fi

# Install the monitoring script
print_info "Installing monitoring script..."
cp "$SCRIPT_DIR/plex-mount-monitor.sh" /usr/local/bin/
chmod +x /usr/local/bin/plex-mount-monitor.sh
print_success "Monitoring script installed to /usr/local/bin/plex-mount-monitor.sh"

# Install the systemd service
print_info "Installing systemd service..."
cp "$SCRIPT_DIR/plex-mount-monitor.service" /etc/systemd/system/
print_success "Service file installed to /etc/systemd/system/plex-mount-monitor.service"

# Reload systemd
print_info "Reloading systemd daemon..."
systemctl daemon-reload
print_success "Systemd daemon reloaded"

# Create log directory if it doesn't exist
LOG_DIR="/var/log"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    print_success "Created log directory: $LOG_DIR"
fi

echo ""
print_success "Installation completed successfully!"
echo ""

# Install test script if available
if [ -f "$SCRIPT_DIR/test-setup.sh" ]; then
    print_info "Installing test script..."
    cp "$SCRIPT_DIR/test-setup.sh" /usr/local/bin/
    chmod +x /usr/local/bin/test-setup.sh
    print_success "Test script installed to /usr/local/bin/test-setup.sh"
    echo ""
fi

# Check if /etc/fstab has mount entries
print_info "Checking /etc/fstab configuration..."
if grep -q "^[^#]*bind" /etc/fstab 2>/dev/null; then
    print_success "Found bind mount entries in /etc/fstab"
else
    print_warning "No bind mount entries found in /etc/fstab"
    echo ""
    print_info "You need to add your mount points to /etc/fstab for automatic remounting."
    echo "Example entries:"
    echo ""
    echo "  /mnt/host/media    /mnt/mp0    none    bind,defaults    0    0"
    echo "  /mnt/host/movies   /mnt/mp1    none    bind,defaults    0    0"
    echo "  /mnt/host/tv       /mnt/mp2    none    bind,defaults    0    0"
    echo ""
    print_info "Edit /etc/fstab with: nano /etc/fstab"
    echo ""
fi

# Ask if user wants to enable and start the service
echo ""
read -p "Do you want to enable and start the service now? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Enabling service..."
    systemctl enable plex-mount-monitor.service
    print_success "Service enabled (will start on boot)"
    
    print_info "Starting service..."
    systemctl start plex-mount-monitor.service
    print_success "Service started"
    
    echo ""
    print_info "Checking service status..."
    sleep 2
    systemctl status plex-mount-monitor.service --no-pager || true
    
    echo ""
    print_success "Installation and setup complete!"
    echo ""
    print_info "Useful commands:"
    echo "  - Check status:  systemctl status plex-mount-monitor.service"
    echo "  - View logs:     journalctl -u plex-mount-monitor.service -f"
    echo "  - View log file: tail -f /var/log/plex-mount-monitor.log"
    echo "  - Stop service:  systemctl stop plex-mount-monitor.service"
    echo "  - Restart:       systemctl restart plex-mount-monitor.service"
else
    echo ""
    print_info "Service not started. You can start it later with:"
    echo "  systemctl enable plex-mount-monitor.service"
    echo "  systemctl start plex-mount-monitor.service"
fi

echo ""
print_success "Done!"