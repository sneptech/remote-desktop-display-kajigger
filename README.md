# RDP Display Switcher

A KDE Plasma 6 plasmoid and daemon that automatically switches display configuration when remote desktop connections are detected.

## Problem

When using RDP or VNC to connect to a multi-monitor Linux desktop, the remote session captures all displays combined into one large canvas. This results in:
- Tiny UI elements on the client device
- Poor aspect ratio matching
- Difficult-to-use remote experience

## Solution

This tool detects incoming RDP/VNC connections and automatically:
1. Saves your current display configuration
2. Disconnects the remote session briefly
3. Disables secondary display(s)
4. Allows reconnection with only the primary display active

When you disconnect, it restores your original multi-monitor setup.

## Features

- Automatic detection of RDP and VNC connections
- Configurable secondary display selection
- System tray plasmoid with status indicators
- Manual switch/restore controls
- Survives daemon restarts and system reboots
- DBus interface for scripting

## Requirements

- KDE Plasma 6.x
- Wayland session
- Python 3.x
- python-dbus
- python-gobject
- libkscreen (for kscreen-doctor)
- qt6-tools (for qdbus)

## Installation

### From Source (User Install)

```bash
git clone https://github.com/yourusername/rdp-display-switcher.git
cd rdp-display-switcher
./scripts/install.sh
```

### From Source (System Install)

```bash
sudo ./scripts/install.sh --system
```

### Arch Linux / CachyOS (AUR)

```bash
yay -S rdp-display-switcher
```

## Usage

### Enable the Daemon

```bash
systemctl --user enable --now rdp-display-manager
```

### Add the Plasmoid

1. Right-click on your panel
2. Select "Add Widgets"
3. Search for "RDP Display Switcher"
4. Drag it to your panel or system tray

### Configuration

Right-click the plasmoid and select "Configure" to set:
- Secondary display output name (e.g., HDMI-A-1)
- RDP/VNC ports to monitor
- Debounce timing
- Notification preferences

## How It Works

### State Machine

```
IDLE -> DETECTED -> SWITCHING -> REMOTE_ACTIVE -> RESTORING -> IDLE
```

1. **IDLE**: Monitoring for connections
2. **DETECTED**: Connection found, waiting for debounce
3. **SWITCHING**: Saving config and disabling secondary display
4. **REMOTE_ACTIVE**: Single-display mode active
5. **RESTORING**: Reconnecting secondary display

### Why Disconnect and Reconnect?

Most VNC/RDP servers do not handle display topology changes during an active session. The cleanest approach is to:
1. Detect the new connection
2. Terminate it immediately
3. Reconfigure displays
4. Let the user reconnect

This adds about 2 seconds of delay but ensures a clean session.

## DBus Interface

The daemon exposes a DBus service at `org.kde.rdpdisplayswitcher`:

```bash
# Get current state
qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher GetState

# Check if enabled
qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher IsEnabled

# Toggle automatic switching
qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher SetEnabled true

# Manual switch to remote mode
qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher SwitchNow

# Manual restore
qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher RestoreNow
```

## Project Structure

```
rdp-display-switcher/
├── README.md
├── LICENSE
├── plasmoid/
│   ├── metadata.json
│   └── contents/
│       ├── ui/
│       │   ├── main.qml
│       │   ├── configGeneral.qml
│       │   └── configDisplay.qml
│       └── config/
│           ├── main.xml
│           └── config.qml
├── daemon/
│   ├── rdp-display-manager.py
│   └── rdp-display-manager.service
├── scripts/
│   └── install.sh
└── package/
    └── PKGBUILD
```

## Troubleshooting

### Daemon not starting

Check the logs:
```bash
journalctl --user -u rdp-display-manager -f
```

### Display not switching

1. Verify kscreen-doctor works:
   ```bash
   kscreen-doctor -o
   ```

2. Check the secondary output name matches your configuration

3. Ensure the daemon can detect connections:
   ```bash
   ss -tn state established '( sport = :3389 )'
   ```

### Plasmoid not appearing

Restart Plasma:
```bash
plasmashell --replace &
```

## Contributing

Contributions are welcome. Please open an issue or pull request on GitHub.

## License

GPL-3.0 - See LICENSE file for details.
