# Plex Mount Monitor

Monitors Proxmox CT bind mounts and automatically remounts them if they fail. Designed for Plex media server containers where bind mounts to host storage can sometimes disconnect.

## What It Does

- **Dynamically detects all bind mounts** (mp0, mp1, mp2, etc.) by scanning `/proc/mounts`
- **Continuously monitors** each mount point for accessibility (checks read access every 60 seconds by default)
- **Auto-remounts** failed mounts using `/etc/fstab` entries
- **Logs everything** to `/var/log/plex-mount-monitor.log` with timestamps and severity levels
- **Runs as a systemd service** for automatic startup and recovery

## Prerequisites

- A Proxmox LXC container (tested on Ubuntu/Debian-based CTs)
- Root access inside the container
- Bind mounts configured in the Proxmox CT configuration (e.g., `mp0`, `mp1`, `mp2`)
- `/etc/fstab` entries for the bind mounts (required for auto-remount to work)

## Files

| File | Description |
|------|-------------|
| `plex-mount-monitor.sh` | The main monitoring script |
| `install.sh` | Installation script for the systemd service |
| `test-setup.sh` | Diagnostic tool to validate your setup |
| `plex-mount-monitor.service` | systemd service unit file |
| `fstab.example` | Example `/etc/fstab` entries for bind mounts |

## Step-by-Step Setup

### 1. Clone or Copy Files

```bash
# On your Proxmox CT:
mkdir -p /usr/local/bin/scripts
# Copy all files from this repo to the CT, or:
cd /usr/local/bin/scripts
git clone https://github.com/Vehask/plex-mount-reload.git
cd plex-mount-reload
```

### 2. Configure Bind Mounts in Proxmox

On your Proxmox host, edit the CT configuration file:

```bash
# On the Proxmox host, not inside the CT
nano /etc/pve/lxc/<CTID>.conf
```

Add entries like:

```
mp0: /mnt/host/media,mp=/mnt/mp0
mp1: /mnt/host/movies,mp=/mnt/mp1
mp2: /mnt/host/tv,mp=/mnt/mp2
```

> **Important:** The `mp0`, `mp1`, etc. entries in the Proxmox config define which directories from the host are passed into the container. The script monitors these mount points and remounts them if they fail.

### 3. Configure /etc/fstab (Inside the CT)

This is **required** for auto-remounting to work:

```bash
# Inside the CT
nano /etc/fstab
```

Add entries matching your Proxmox bind mount configuration:

```
# Format: <source> <mount_point> <type> <options> <dump> <pass>
/mnt/host/media    /mnt/mp0    none    bind,defaults    0    0
/mnt/host/movies   /mnt/mp1    none    bind,defaults    0    0
/mnt/host/tv       /mnt/mp2    none    bind,defaults    0    0
```

Replace `/mnt/host/...` with the actual source paths from your Proxmox CT config (the first part of the `mp0:` entry).

Test your fstab:

```bash
mount -a
```

### 4. Run the Installer

```bash
cd /usr/local/bin/scripts/plex-mount-reload
chmod +x install.sh plex-mount-monitor.sh test-setup.sh
./install.sh
```

The installer will:
- Copy the monitoring script to `/usr/local/bin/`
- Install the systemd service unit
- Copy the test script
- Optionally enable and start the service

### 5. Verify the Setup

```bash
# Run the test script
/usr/local/bin/test-setup.sh
```

### 6. Test the Service

```bash
# Check service status
systemctl status plex-mount-monitor.service

# View live logs
journalctl -u plex-mount-monitor.service -f

# View the log file
tail -f /var/log/plex-mount-monitor.log
```

## Usage

### Command-Line Options

```bash
plex-mount-monitor.sh [options]

Options:
  -i, --interval SECONDS    Check interval in seconds (default: 60)
  -l, --log FILE           Log file path (default: /var/log/plex-mount-monitor.log)
  -v, --verbose            Enable verbose logging
  -h, --help               Show help message
```

### Manual Test

```bash
# Run once with verbose output (uses default 60s interval, runs continuously)
/usr/local/bin/plex-mount-monitor.sh --verbose

# Run with custom interval (every 30 seconds)
/usr/local/bin/plex-mount-monitor.sh --interval 30
```

## How the Script Works

1. **Detection Phase**: Reads `/proc/mounts` to find all bind mounts, filtering out system mounts.
2. **Monitoring Loop**: Every N seconds (default 60), checks each mount point:
   - Does the directory exist?
   - Is it a valid mount point (`mountpoint -q`)?
   - Is it accessible (`ls` test with 5-second timeout)?
3. **Remediation**: If a mount fails:
   - Attempts graceful unmount (`umount`)
   - Falls back to lazy unmount (`umount -l`) if needed
   - Remounts using `/etc/fstab` entry
   - Verifies the remount was successful
4. **Dynamic Tracking**: Detects new mounts automatically and removes mounts that no longer exist.

## Troubleshooting

### "No bind mount entries in /etc/fstab"

The script needs fstab entries to remount failed mounts. See the [fstab configuration](#3-configure-etc-fstab-inside-the-ct) section above.

### Service won't start

Check the service logs:

```bash
journalctl -u plex-mount-monitor.service --no-pager
```

### Mount points not detected

Run the script manually with verbose mode to see what it's detecting:

```bash
/usr/local/bin/plex-mount-monitor.sh --verbose
```

### Common Issues

- **Bind mounts not configured in Proxmox CT config** — Add `mp0:`, `mp1:` entries to `/etc/pve/lxc/<CTID>.conf`
- **fstab doesn't match actual mount sources** — Check Proxmox config and ensure sources match
- **Permission denied** — Run the script as root (or let the systemd service handle it)

## Useful Commands

```bash
# Check service status
systemctl status plex-mount-monitor.service

# View live service logs
journalctl -u plex-mount-monitor.service -f

# View the log file
tail -f /var/log/plex-mount-monitor.log

# Restart the service
systemctl restart plex-mount-monitor.service

# Stop the service
systemctl stop plex-mount-monitor.service

# Disable auto-start
systemctl disable plex-mount-monitor.service
```

## License

MIT