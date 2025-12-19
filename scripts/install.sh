#!/bin/bash
#
# RDP Display Switcher Installation Script
#
# Usage: ./install.sh [--uninstall]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Installation paths
DAEMON_DIR="$HOME/.local/share/rdp-display-switcher"
SERVICE_DIR="$HOME/.config/systemd/user"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.kde.rdpdisplayswitcher"
STATE_DIR="$HOME/.local/state/rdp-display-switcher"

install() {
    echo "Installing RDP Display Switcher..."

    # Create directories
    mkdir -p "$DAEMON_DIR"
    mkdir -p "$SERVICE_DIR"
    mkdir -p "$PLASMOID_DIR/contents/ui"
    mkdir -p "$PLASMOID_DIR/contents/config"
    mkdir -p "$STATE_DIR"

    # Install daemon
    echo "  -> Daemon"
    cp "$PROJECT_DIR/daemon/rdp-display-manager.py" "$DAEMON_DIR/"
    chmod +x "$DAEMON_DIR/rdp-display-manager.py"

    # Install systemd service with correct path
    echo "  -> Systemd service"
    sed "s|/usr/share/rdp-display-switcher|$DAEMON_DIR|g" \
        "$PROJECT_DIR/daemon/rdp-display-manager.service" > "$SERVICE_DIR/rdp-display-manager.service"

    # Install plasmoid
    echo "  -> Plasmoid"
    cp "$PROJECT_DIR/plasmoid/metadata.json" "$PLASMOID_DIR/"
    cp "$PROJECT_DIR/plasmoid/contents/ui/"*.qml "$PLASMOID_DIR/contents/ui/"
    cp "$PROJECT_DIR/plasmoid/contents/config/"* "$PLASMOID_DIR/contents/config/"

    # Reload systemd
    echo "  -> Reloading systemd"
    systemctl --user daemon-reload

    # Restart daemon if running, otherwise start it
    if systemctl --user is-active --quiet rdp-display-manager; then
        echo "  -> Restarting daemon"
        systemctl --user restart rdp-display-manager
    else
        echo "  -> Starting daemon"
        systemctl --user enable --now rdp-display-manager
    fi

    echo ""
    echo "Done! Restart plasmashell to reload the widget:"
    echo "  plasmashell --replace &"
    echo ""
    echo "Or run this to do it now:"
    echo "  kquitapp6 plasmashell && kstart plasmashell"
}

uninstall() {
    echo "Uninstalling RDP Display Switcher..."

    systemctl --user stop rdp-display-manager 2>/dev/null || true
    systemctl --user disable rdp-display-manager 2>/dev/null || true

    rm -rf "$DAEMON_DIR"
    rm -f "$SERVICE_DIR/rdp-display-manager.service"
    rm -rf "$PLASMOID_DIR"
    rm -rf "$STATE_DIR"
    rm -rf "/tmp/rdp-display-switcher"

    systemctl --user daemon-reload

    echo "Done!"
}

case "${1:-}" in
    --uninstall|-u)
        uninstall
        ;;
    *)
        install
        ;;
esac
