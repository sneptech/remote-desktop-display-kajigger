# Last Agent Session - December 20, 2025

## Project Overview

**RDP Display Switcher** - A KDE Plasma 6 plasmoid + daemon that automatically switches display configuration when remote desktop (RDP/VNC) connections are detected.

### The Problem
When remoting into a multi-monitor Linux desktop, the remote session captures ALL displays combined into one tall canvas. This results in tiny UI elements and poor aspect ratio on the client device.

### The Solution
Automatically detect RDP/VNC connections, disable secondary display(s), let user reconnect with only the primary display active. Restore displays when disconnected.

---

## What Was Successfully Completed

### 1. Project Structure Created
```
rdp-display-switcher/
├── daemon/
│   ├── rdp-display-manager.py      # Python daemon with DBus interface
│   └── rdp-display-manager.service # systemd user service
├── plasmoid/
│   ├── metadata.json               # KDE Plasma 6 metadata
│   └── contents/
│       ├── ui/
│       │   ├── main.qml            # Main plasmoid UI
│       │   ├── configGeneral.qml   # General settings page
│       │   └── configDisplay.qml   # Display settings page
│       └── config/
│           ├── main.xml            # Configuration schema
│           └── config.qml          # Config page definitions
├── scripts/
│   └── install.sh                  # Installation script (works!)
├── package/
│   └── PKGBUILD                    # AUR package build
├── README.md
└── LICENSE
```

### 2. Daemon Features Implemented
- DBus service at `org.kde.rdpdisplayswitcher`
- Connection monitoring (polls ports 3389/RDP, 5900-5902/VNC)
- State machine: IDLE → DETECTED → SWITCHING → REMOTE_ACTIVE → RESTORING
- Display management via `kscreen-doctor`
- Methods: `GetState`, `GetDisplays`, `GetFullStatus`, `SetSecondaryOutput`, `SwitchNow`, `RestoreNow`
- Writes status to `/tmp/rdp-display-switcher/status.json` and `displays.json`
- Crash recovery (saves state to disk)

### 3. Plasmoid UI Implemented
- System tray icon with status indicator
- Popup showing: daemon status, state, connections, secondary display
- "Scan Displays" button (UI works, but doesn't get data - see issues below)
- Display list with clickable buttons to select secondary
- Enable/disable toggle for automatic switching
- Manual "Switch to Remote" / "Restore Displays" buttons

### 4. Install Script Works
- `./scripts/install.sh` properly installs everything
- Creates systemd user service
- Copies plasmoid files
- Sets `QML_XHR_ALLOW_FILE_READ=1` environment variable
- Starts/restarts daemon

---

## Current Issues (What's Broken)

### Issue 1: kscreen-doctor Returns Empty Output from Daemon
**Status:** BLOCKING - Primary issue

The daemon runs but `kscreen-doctor -o` returns empty output when executed from the systemd service context. Running `kscreen-doctor -o` directly in a terminal works fine.

**Cause:** The systemd user service doesn't have access to the Wayland display session environment variables (`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`).

**Evidence:**
```
journalctl --user -u rdp-display-manager -f
Dec 20 05:49:08 dreamtime python3[8377]: 2025-12-20 05:49:08,023 - INFO - Found 0 displays: []
```

**Attempted fix (not yet tested):** Added to service file:
```ini
PassEnvironment=WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS
```

**Alternative solutions to try:**
1. Don't use systemd - run daemon directly from autostart
2. Use `systemctl --user import-environment` before starting service
3. Create a wrapper script that sources the environment first
4. Use `Environment=` directives in the service file with hardcoded paths

### Issue 2: Plasmoid Can't Read Local Files (XMLHttpRequest blocked)
**Status:** Workaround implemented, requires logout/login

QML blocks `XMLHttpRequest` from reading local files by default:
```
XMLHttpRequest: Using GET on a local file is disabled by default.
Set QML_XHR_ALLOW_FILE_READ to 1 to enable this feature.
```

**Fix implemented:** Install script creates `~/.config/environment.d/rdp-display-switcher.conf` with:
```
QML_XHR_ALLOW_FILE_READ=1
```

**Requires:** User must LOG OUT and LOG BACK IN for this to take effect.

### Issue 3: Plasmoid sendCommand() Doesn't Execute
**Status:** Known limitation

The `sendCommand()` function in the plasmoid only does `console.log()` - it doesn't actually execute DBus commands. This is because:
- `PlasmaCore.DataSource` with executable engine is deprecated in Plasma 6
- No easy way to run shell commands from QML in Plasma 6
- The file-based approach was chosen instead (daemon writes, plasmoid reads)

**This is fine IF** the daemon properly writes to the status files - which requires fixing Issue 1 first.

---

## Next Steps to Fix

### Priority 1: Fix kscreen-doctor Environment
The daemon needs Wayland session environment. Options:

**Option A: Wrapper script approach**
Create `/home/max/.local/share/rdp-display-switcher/start-daemon.sh`:
```bash
#!/bin/bash
# Import environment from running session
export $(dbus-launch)
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
exec python3 /home/max/.local/share/rdp-display-switcher/rdp-display-manager.py
```
Update service file `ExecStart=` to use the wrapper.

**Option B: Autostart instead of systemd**
Create `~/.config/autostart/rdp-display-manager.desktop`:
```ini
[Desktop Entry]
Type=Application
Name=RDP Display Manager
Exec=python3 /home/max/.local/share/rdp-display-switcher/rdp-display-manager.py
X-KDE-autostart-phase=2
```
Remove the systemd service.

**Option C: Fix service environment**
In the service file, try:
```ini
[Service]
Environment="WAYLAND_DISPLAY=wayland-0"
Environment="XDG_RUNTIME_DIR=/run/user/1000"
```

### Priority 2: Test After Environment Fix
Once kscreen-doctor works from daemon:
1. Check `/tmp/rdp-display-switcher/displays.json` has content
2. Log out and back in (for QML_XHR env var)
3. Open plasmoid, click "Scan Displays"
4. Should now show the display buttons

### Priority 3: Test Full Flow
1. Connect via VNC/RDP
2. Verify daemon detects connection
3. Verify display switches
4. Verify restore on disconnect

---

## User's System Info
- **OS:** CachyOS Linux (Arch-based)
- **KDE Plasma:** 6.5.4
- **KDE Frameworks:** 6.21.0
- **Qt:** 6.10.1
- **Kernel:** 6.18.1-2-cachyos
- **Display Server:** Wayland
- **Displays:**
  - HDMI-A-1: 1920x1080@144Hz (priority 1, primary)
  - DP-1: 2560x1440@74Hz (priority 2)

---

## Key Files to Review

1. **Daemon:** `daemon/rdp-display-manager.py`
   - `GetDisplays()` method parses kscreen-doctor output
   - `_write_status_files()` writes to /tmp for plasmoid
   - Currently has DEBUG logging enabled

2. **Service:** `daemon/rdp-display-manager.service`
   - Needs environment variables for Wayland access

3. **Plasmoid:** `plasmoid/contents/ui/main.qml`
   - Reads from `/tmp/rdp-display-switcher/*.json`
   - Uses XMLHttpRequest (needs QML_XHR_ALLOW_FILE_READ=1)

4. **Install:** `scripts/install.sh`
   - Run this after any changes to deploy

---

## Quick Test Commands

```bash
# Check if daemon is running
systemctl --user status rdp-display-manager

# View daemon logs
journalctl --user -u rdp-display-manager -f

# Check if kscreen-doctor works in terminal
kscreen-doctor -o

# Check daemon's output files
cat /tmp/rdp-display-switcher/status.json
cat /tmp/rdp-display-switcher/displays.json

# Restart daemon after changes
./scripts/install.sh

# Restart plasmashell to reload widget
kquitapp6 plasmashell && kstart plasmashell
```

---

## Session Summary

This session created the full project structure and implemented all the core functionality. The main remaining issue is getting the systemd service to have proper access to the Wayland display session so `kscreen-doctor` can enumerate displays. Once that's fixed, everything should work together.
