#!/bin/bash
#
# RDP Display Switcher Installation Script
#
# This script installs the RDP Display Switcher daemon and plasmoid.
#
# Usage: ./install.sh [--user|--system]
#   --user   Install for current user only (default)
#   --system Install system-wide (requires root)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Installation mode
INSTALL_MODE="user"
if [[ "$1" == "--system" ]]; then
    INSTALL_MODE="system"
fi

echo -e "${GREEN}RDP Display Switcher Installer${NC}"
echo "================================"
echo ""

# Check dependencies
check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"

    local missing=()

    # Required commands
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi

    if ! command -v kscreen-doctor &> /dev/null; then
        missing+=("kscreen-doctor (libkscreen)")
    fi

    if ! command -v qdbus &> /dev/null; then
        missing+=("qdbus (qt6-tools)")
    fi

    # Check Python modules
    if ! python3 -c "import dbus" 2>/dev/null; then
        missing+=("python-dbus")
    fi

    if ! python3 -c "from gi.repository import GLib" 2>/dev/null; then
        missing+=("python-gobject")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing dependencies:${NC}"
        printf '  - %s\n' "${missing[@]}"
        echo ""
        echo "Install on Arch/CachyOS:"
        echo "  sudo pacman -S python python-dbus python-gobject libkscreen qt6-tools"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}All dependencies satisfied!${NC}"
}

# Install for current user
install_user() {
    echo -e "${YELLOW}Installing for current user...${NC}"

    local DAEMON_DIR="$HOME/.local/share/rdp-display-switcher"
    local SERVICE_DIR="$HOME/.config/systemd/user"
    local PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.kde.rdpdisplayswitcher"
    local CONFIG_DIR="$HOME/.config/rdp-display-switcher"
    local STATE_DIR="$HOME/.local/state/rdp-display-switcher"

    # Create directories
    mkdir -p "$DAEMON_DIR"
    mkdir -p "$SERVICE_DIR"
    mkdir -p "$PLASMOID_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$STATE_DIR"

    # Install daemon
    echo "  Installing daemon..."
    cp "$PROJECT_DIR/daemon/rdp-display-manager.py" "$DAEMON_DIR/"
    chmod +x "$DAEMON_DIR/rdp-display-manager.py"

    # Install systemd service (with correct path)
    echo "  Installing systemd service..."
    sed "s|/usr/share/rdp-display-switcher|$DAEMON_DIR|g" \
        "$PROJECT_DIR/daemon/rdp-display-manager.service" > "$SERVICE_DIR/rdp-display-manager.service"

    # Install plasmoid
    echo "  Installing plasmoid..."
    cp -r "$PROJECT_DIR/plasmoid/"* "$PLASMOID_DIR/"

    # Reload systemd and enable service
    echo "  Enabling systemd service..."
    systemctl --user daemon-reload
    systemctl --user enable rdp-display-manager.service

    echo -e "${GREEN}Installation complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Start the daemon: systemctl --user start rdp-display-manager"
    echo "  2. Add the plasmoid to your panel or system tray"
    echo "  3. Configure your secondary display in the plasmoid settings"
    echo ""
}

# Install system-wide
install_system() {
    echo -e "${YELLOW}Installing system-wide (requires root)...${NC}"

    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: System installation requires root privileges${NC}"
        echo "Run with: sudo ./install.sh --system"
        exit 1
    fi

    local DAEMON_DIR="/usr/share/rdp-display-switcher"
    local SERVICE_DIR="/usr/lib/systemd/user"
    local PLASMOID_DIR="/usr/share/plasma/plasmoids/org.kde.rdpdisplayswitcher"

    # Create directories
    mkdir -p "$DAEMON_DIR"
    mkdir -p "$SERVICE_DIR"
    mkdir -p "$PLASMOID_DIR"

    # Install daemon
    echo "  Installing daemon..."
    install -Dm755 "$PROJECT_DIR/daemon/rdp-display-manager.py" "$DAEMON_DIR/rdp-display-manager.py"

    # Install systemd service
    echo "  Installing systemd service..."
    install -Dm644 "$PROJECT_DIR/daemon/rdp-display-manager.service" "$SERVICE_DIR/rdp-display-manager.service"

    # Install plasmoid
    echo "  Installing plasmoid..."
    cp -r "$PROJECT_DIR/plasmoid/"* "$PLASMOID_DIR/"

    echo -e "${GREEN}System installation complete!${NC}"
    echo ""
    echo "Each user needs to enable the service:"
    echo "  systemctl --user enable --now rdp-display-manager"
    echo ""
}

# Uninstall for current user
uninstall_user() {
    echo -e "${YELLOW}Uninstalling for current user...${NC}"

    # Stop and disable service
    systemctl --user stop rdp-display-manager.service 2>/dev/null || true
    systemctl --user disable rdp-display-manager.service 2>/dev/null || true

    # Remove files
    rm -rf "$HOME/.local/share/rdp-display-switcher"
    rm -f "$HOME/.config/systemd/user/rdp-display-manager.service"
    rm -rf "$HOME/.local/share/plasma/plasmoids/org.kde.rdpdisplayswitcher"

    # Reload systemd
    systemctl --user daemon-reload

    echo -e "${GREEN}Uninstallation complete!${NC}"
}

# Main
case "${1:-}" in
    --uninstall)
        uninstall_user
        ;;
    --system)
        check_dependencies
        install_system
        ;;
    *)
        check_dependencies
        install_user
        ;;
esac
