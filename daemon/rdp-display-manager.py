#!/usr/bin/env python3
"""
RDP Display Manager Daemon

Monitors for RDP/VNC connections and automatically switches display configuration
to provide a better remote desktop experience.

Author: RDP Display Switcher Project
License: GPL-3.0
"""

import subprocess
import json
import time
import signal
import sys
import os
import logging
from pathlib import Path
from enum import Enum, auto
from typing import Optional
from threading import Thread, Event

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

# Configuration
POLL_INTERVAL = 2  # seconds
DEBOUNCE_TIME = 3  # seconds - wait before acting on connection changes
STATE_FILE = Path.home() / ".local/state/rdp-display-switcher/state.json"
CONFIG_FILE = Path.home() / ".config/rdp-display-switcher/config.json"
CACHE_DIR = Path("/tmp/rdp-display-switcher")
STATUS_FILE = CACHE_DIR / "status.json"
DISPLAYS_FILE = CACHE_DIR / "displays.json"

# DBus configuration
DBUS_SERVICE_NAME = "org.kde.rdpdisplayswitcher"
DBUS_OBJECT_PATH = "/org/kde/rdpdisplayswitcher"
DBUS_INTERFACE = "org.kde.rdpdisplayswitcher"

# Set up logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(Path.home() / ".local/state/rdp-display-switcher/daemon.log")
    ]
)
logger = logging.getLogger(__name__)


def _build_kscreen_env() -> dict:
    """Build an environment for kscreen-doctor when running under systemd."""
    env = dict(os.environ)
    uid = os.getuid()

    runtime_dir = env.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        candidate = f"/run/user/{uid}"
        if os.path.isdir(candidate):
            runtime_dir = candidate
            env["XDG_RUNTIME_DIR"] = runtime_dir
            logger.debug("Set XDG_RUNTIME_DIR to %s", runtime_dir)

    if runtime_dir and "DBUS_SESSION_BUS_ADDRESS" not in env:
        bus_path = os.path.join(runtime_dir, "bus")
        if os.path.exists(bus_path):
            env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={bus_path}"
            logger.debug("Set DBUS_SESSION_BUS_ADDRESS to %s", env["DBUS_SESSION_BUS_ADDRESS"])

    if runtime_dir and "WAYLAND_DISPLAY" not in env:
        for name in ("wayland-0", "wayland-1", "wayland-2"):
            if os.path.exists(os.path.join(runtime_dir, name)):
                env["WAYLAND_DISPLAY"] = name
                logger.debug("Set WAYLAND_DISPLAY to %s", name)
                break
        if "WAYLAND_DISPLAY" not in env:
            try:
                for entry in os.listdir(runtime_dir):
                    if entry.startswith("wayland-"):
                        env["WAYLAND_DISPLAY"] = entry
                        logger.debug("Set WAYLAND_DISPLAY to %s", entry)
                        break
            except OSError:
                pass

    return env


class State(Enum):
    """Daemon state machine states"""
    IDLE = auto()           # Normal operation, monitoring for connections
    DETECTED = auto()       # Connection detected, waiting for debounce
    SWITCHING = auto()      # Actively switching display configuration
    REMOTE_ACTIVE = auto()  # Remote session is active, single display mode
    RESTORING = auto()      # Restoring original display configuration
    DISABLED = auto()       # Automatic switching disabled


class DisplayConfig:
    """Manages display configuration using kscreen-doctor"""

    def __init__(self, secondary_output: str = "HDMI-A-1"):
        self.secondary_output = secondary_output
        self.saved_config: Optional[dict] = None

    def get_current_config(self) -> dict:
        """Get current display configuration"""
        try:
            result = subprocess.run(
                ["kscreen-doctor", "-j"],
                capture_output=True,
                text=True,
                env=_build_kscreen_env(),
                timeout=10
            )
            if result.returncode == 0:
                return json.loads(result.stdout)
            else:
                logger.error(f"kscreen-doctor failed: {result.stderr}")
                return {}
        except subprocess.TimeoutExpired:
            logger.error("kscreen-doctor timed out")
            return {}
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse kscreen-doctor output: {e}")
            return {}
        except FileNotFoundError:
            logger.error("kscreen-doctor not found")
            return {}

    def save_current_config(self) -> bool:
        """Save current display configuration for later restoration"""
        self.saved_config = self.get_current_config()
        if self.saved_config:
            # Also save to disk in case daemon crashes
            self._save_to_disk()
            logger.info("Display configuration saved")
            return True
        return False

    def _save_to_disk(self):
        """Persist saved config to disk"""
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(STATE_FILE, 'w') as f:
            json.dump({
                "saved_config": self.saved_config,
                "secondary_output": self.secondary_output,
                "timestamp": time.time()
            }, f, indent=2)

    def _load_from_disk(self) -> bool:
        """Load saved config from disk (for crash recovery)"""
        if STATE_FILE.exists():
            try:
                with open(STATE_FILE) as f:
                    data = json.load(f)
                    self.saved_config = data.get("saved_config")
                    return self.saved_config is not None
            except (json.JSONDecodeError, IOError) as e:
                logger.error(f"Failed to load state file: {e}")
        return False

    def _clear_disk_state(self):
        """Clear the saved state file"""
        if STATE_FILE.exists():
            STATE_FILE.unlink()

    def disable_secondary(self) -> bool:
        """Disable the secondary display"""
        try:
            result = subprocess.run(
                ["kscreen-doctor", f"output.{self.secondary_output}.disable"],
                capture_output=True,
                text=True,
                env=_build_kscreen_env(),
                timeout=10
            )
            if result.returncode == 0:
                logger.info(f"Disabled {self.secondary_output}")
                return True
            else:
                logger.error(f"Failed to disable display: {result.stderr}")
                return False
        except subprocess.TimeoutExpired:
            logger.error("kscreen-doctor timed out while disabling display")
            return False
        except FileNotFoundError:
            logger.error("kscreen-doctor not found")
            return False

    def restore_config(self) -> bool:
        """Restore the saved display configuration"""
        if not self.saved_config:
            # Try to load from disk
            if not self._load_from_disk():
                logger.warning("No saved configuration to restore")
                return False

        # Find the secondary output configuration
        outputs = self.saved_config.get("outputs", [])
        secondary = None
        for output in outputs:
            if output.get("name") == self.secondary_output:
                secondary = output
                break

        if not secondary:
            logger.error(f"Secondary output {self.secondary_output} not found in saved config")
            return False

        # Build the kscreen-doctor command to restore
        # Example: output.HDMI-A-1.enable output.HDMI-A-1.position.0,-1080 output.HDMI-A-1.mode.1920x1080@60
        commands = [f"output.{self.secondary_output}.enable"]

        pos = secondary.get("pos", {})
        if pos:
            commands.append(f"output.{self.secondary_output}.position.{pos.get('x', 0)},{pos.get('y', 0)}")

        mode = secondary.get("currentMode", {})
        if mode:
            width = mode.get("width", 1920)
            height = mode.get("height", 1080)
            refresh = mode.get("refreshRate", 60)
            commands.append(f"output.{self.secondary_output}.mode.{width}x{height}@{int(refresh)}")

        try:
            result = subprocess.run(
                ["kscreen-doctor"] + commands,
                capture_output=True,
                text=True,
                env=_build_kscreen_env(),
                timeout=10
            )
            if result.returncode == 0:
                logger.info(f"Restored display configuration for {self.secondary_output}")
                self._clear_disk_state()
                self.saved_config = None
                return True
            else:
                logger.error(f"Failed to restore display: {result.stderr}")
                return False
        except subprocess.TimeoutExpired:
            logger.error("kscreen-doctor timed out while restoring display")
            return False
        except FileNotFoundError:
            logger.error("kscreen-doctor not found")
            return False


class ConnectionMonitor:
    """Monitors for RDP and VNC connections"""

    def __init__(self, rdp_ports: list = None, vnc_ports: list = None):
        self.rdp_ports = rdp_ports or [3389]
        self.vnc_ports = vnc_ports or [5900, 5901, 5902]
        self._last_connection_count = 0

    def check_connections(self) -> dict:
        """Check for active RDP/VNC connections"""
        connections = {
            "rdp": [],
            "vnc": [],
            "total": 0
        }

        # Check RDP connections
        for port in self.rdp_ports:
            conns = self._check_port(port)
            connections["rdp"].extend(conns)

        # Check VNC connections
        for port in self.vnc_ports:
            conns = self._check_port(port)
            connections["vnc"].extend(conns)

        connections["total"] = len(connections["rdp"]) + len(connections["vnc"])
        return connections

    def _check_port(self, port: int) -> list:
        """Check for established connections on a specific port"""
        try:
            result = subprocess.run(
                ["ss", "-tn", "state", "established", f"( sport = :{port} )"],
                capture_output=True,
                text=True,
                timeout=5
            )
            connections = []
            for line in result.stdout.strip().split('\n')[1:]:  # Skip header
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 4:
                        connections.append({
                            "local": parts[3],
                            "remote": parts[4] if len(parts) > 4 else "unknown"
                        })
            return connections
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            logger.error(f"Failed to check port {port}: {e}")
            return []

    def has_remote_connection(self) -> bool:
        """Quick check if any remote connection exists"""
        return self.check_connections()["total"] > 0


class SessionManager:
    """Manages RDP/VNC session termination for clean reconnection"""

    @staticmethod
    def terminate_rdp_sessions() -> bool:
        """Terminate active RDP sessions (for krdpserver)"""
        try:
            # Try to terminate via systemctl
            result = subprocess.run(
                ["systemctl", "--user", "restart", "plasma-krdp"],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                logger.info("Restarted plasma-krdp service")
                return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

        # Fallback: try to kill any krdp processes
        try:
            subprocess.run(["pkill", "-f", "krdp"], timeout=5)
            logger.info("Killed krdp processes")
            return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

        return False

    @staticmethod
    def terminate_vnc_sessions() -> bool:
        """Terminate active VNC sessions"""
        try:
            # Try krfb first
            subprocess.run(["pkill", "-f", "krfb"], timeout=5)
            # Also try wayvnc
            subprocess.run(["pkill", "-f", "wayvnc"], timeout=5)
            logger.info("Terminated VNC sessions")
            return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        return False


class RdpDisplaySwitcherService(dbus.service.Object):
    """DBus service for the RDP Display Switcher"""

    def __init__(self, bus_name):
        super().__init__(bus_name, DBUS_OBJECT_PATH)

        self.state = State.IDLE
        self.enabled = True
        self.display_config = DisplayConfig()
        self.connection_monitor = ConnectionMonitor()
        self.session_manager = SessionManager()

        self._debounce_timer = None
        self._stop_event = Event()

        # Load configuration
        self._load_config()

        # Check for crash recovery
        self._check_crash_recovery()

        # Start monitoring thread
        self._monitor_thread = Thread(target=self._monitor_loop, daemon=True)
        self._monitor_thread.start()

        logger.info("RDP Display Switcher daemon started")

        # Write initial status
        self._write_status_files()

    def _write_status_files(self):
        """Write status to cache files for plasmoid to read"""
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)

            # Write status
            connections = self.connection_monitor.check_connections()
            status = {
                "state": self.state.name,
                "enabled": self.enabled,
                "remoteActive": self.state == State.REMOTE_ACTIVE,
                "secondaryOutput": self.display_config.secondary_output,
                "rdpConnections": len(connections["rdp"]),
                "vncConnections": len(connections["vnc"])
            }
            with open(STATUS_FILE, 'w') as f:
                json.dump(status, f)

            # Write displays
            displays_json = self.GetDisplays()
            with open(DISPLAYS_FILE, 'w') as f:
                f.write(displays_json)

        except Exception as e:
            logger.error(f"Failed to write status files: {e}")

    def _load_config(self):
        """Load configuration from disk"""
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    config = json.load(f)
                    self.enabled = config.get("enabled", True)
                    self.display_config.secondary_output = config.get(
                        "secondary_output", "HDMI-A-1"
                    )
                    self.connection_monitor.rdp_ports = config.get(
                        "rdp_ports", [3389]
                    )
                    self.connection_monitor.vnc_ports = config.get(
                        "vnc_ports", [5900, 5901, 5902]
                    )
                    logger.info("Loaded configuration")
            except (json.JSONDecodeError, IOError) as e:
                logger.error(f"Failed to load config: {e}")

    def _save_config(self):
        """Save configuration to disk"""
        config = {
            "enabled": self.enabled,
            "secondary_output": self.display_config.secondary_output,
            "rdp_ports": self.connection_monitor.rdp_ports,
            "vnc_ports": self.connection_monitor.vnc_ports
        }
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(config, f, indent=2)
        except IOError as e:
            logger.error(f"Failed to save config: {e}")

    def _check_crash_recovery(self):
        """Check if we need to recover from a crash during remote session"""
        if STATE_FILE.exists():
            logger.warning("Found state file from previous session - attempting recovery")
            if self.display_config._load_from_disk():
                logger.info("Restoring display configuration from crash recovery")
                self.display_config.restore_config()

    def _monitor_loop(self):
        """Main monitoring loop running in background thread"""
        while not self._stop_event.is_set():
            try:
                self._check_connections()
                # Update status files for plasmoid
                GLib.idle_add(self._write_status_files)
            except Exception as e:
                logger.error(f"Error in monitor loop: {e}")

            self._stop_event.wait(POLL_INTERVAL)

    def _check_connections(self):
        """Check for connection changes and act accordingly"""
        if not self.enabled or self.state == State.DISABLED:
            return

        has_connection = self.connection_monitor.has_remote_connection()

        if self.state == State.IDLE and has_connection:
            # New connection detected
            logger.info("Remote connection detected")
            self._transition_to(State.DETECTED)
            # Start debounce timer
            GLib.timeout_add_seconds(DEBOUNCE_TIME, self._on_debounce_complete)

        elif self.state == State.REMOTE_ACTIVE and not has_connection:
            # Connection dropped
            logger.info("Remote connection ended")
            self._transition_to(State.RESTORING)
            self._restore_displays()

    def _on_debounce_complete(self):
        """Called after debounce period to confirm connection"""
        if self.state != State.DETECTED:
            return False  # Don't repeat

        if self.connection_monitor.has_remote_connection():
            logger.info("Connection confirmed after debounce, switching displays")
            self._switch_to_remote_mode()
        else:
            logger.info("Connection dropped during debounce, returning to idle")
            self._transition_to(State.IDLE)

        return False  # Don't repeat

    def _switch_to_remote_mode(self):
        """Switch to single-display remote mode"""
        self._transition_to(State.SWITCHING)

        # Save current config
        if not self.display_config.save_current_config():
            logger.error("Failed to save display config, aborting switch")
            self._transition_to(State.IDLE)
            return

        # Terminate existing sessions
        self.session_manager.terminate_rdp_sessions()
        self.session_manager.terminate_vnc_sessions()

        # Brief pause to let sessions terminate
        time.sleep(1)

        # Disable secondary display
        if self.display_config.disable_secondary():
            logger.info("Switched to remote mode - secondary display disabled")
            self._transition_to(State.REMOTE_ACTIVE)
            self.RemoteModeChanged(True)
        else:
            logger.error("Failed to disable secondary display")
            self._transition_to(State.IDLE)

    def _restore_displays(self):
        """Restore original display configuration"""
        self._transition_to(State.RESTORING)

        if self.display_config.restore_config():
            logger.info("Display configuration restored")
        else:
            logger.error("Failed to restore display configuration")

        self._transition_to(State.IDLE)
        self.RemoteModeChanged(False)

    def _transition_to(self, new_state: State):
        """Transition to a new state and emit signal"""
        old_state = self.state
        self.state = new_state
        logger.debug(f"State transition: {old_state.name} -> {new_state.name}")
        self.StateChanged(new_state.name)

    def stop(self):
        """Stop the daemon"""
        self._stop_event.set()
        if self._monitor_thread.is_alive():
            self._monitor_thread.join(timeout=5)
        # Clean up status files
        try:
            if STATUS_FILE.exists():
                STATUS_FILE.unlink()
        except Exception:
            pass
        logger.info("Daemon stopped")

    # DBus Methods

    @dbus.service.method(DBUS_INTERFACE, out_signature='s')
    def GetState(self) -> str:
        """Get current daemon state"""
        return self.state.name

    @dbus.service.method(DBUS_INTERFACE, out_signature='b')
    def IsEnabled(self) -> bool:
        """Check if automatic switching is enabled"""
        return self.enabled

    @dbus.service.method(DBUS_INTERFACE, in_signature='b')
    def SetEnabled(self, enabled: bool):
        """Enable or disable automatic switching"""
        self.enabled = enabled
        if not enabled:
            self._transition_to(State.DISABLED)
        else:
            self._transition_to(State.IDLE)
        self._save_config()
        self.EnabledChanged(enabled)
        logger.info(f"Automatic switching {'enabled' if enabled else 'disabled'}")

    @dbus.service.method(DBUS_INTERFACE, out_signature='b')
    def IsRemoteActive(self) -> bool:
        """Check if currently in remote mode"""
        return self.state == State.REMOTE_ACTIVE

    @dbus.service.method(DBUS_INTERFACE, out_signature='a{sv}')
    def GetConnectionInfo(self) -> dict:
        """Get current connection information"""
        connections = self.connection_monitor.check_connections()
        return {
            "rdp_count": dbus.Int32(len(connections["rdp"])),
            "vnc_count": dbus.Int32(len(connections["vnc"])),
            "total": dbus.Int32(connections["total"])
        }

    @dbus.service.method(DBUS_INTERFACE)
    def SwitchNow(self):
        """Manually trigger switch to remote mode"""
        if self.state == State.IDLE:
            logger.info("Manual switch to remote mode requested")
            self._switch_to_remote_mode()

    @dbus.service.method(DBUS_INTERFACE)
    def RestoreNow(self):
        """Manually restore display configuration"""
        if self.state == State.REMOTE_ACTIVE:
            logger.info("Manual restore requested")
            self._restore_displays()

    @dbus.service.method(DBUS_INTERFACE, in_signature='s')
    def SetSecondaryOutput(self, output: str):
        """Set the secondary output to manage"""
        self.display_config.secondary_output = output
        self._save_config()
        logger.info(f"Secondary output set to: {output}")

    @dbus.service.method(DBUS_INTERFACE, out_signature='s')
    def GetSecondaryOutput(self) -> str:
        """Get the secondary output name"""
        return self.display_config.secondary_output

    @dbus.service.method(DBUS_INTERFACE, out_signature='s')
    def GetDisplays(self) -> str:
        """Get list of available displays as JSON string"""
        import re
        try:
            result = subprocess.run(
                ["kscreen-doctor", "-o"],
                capture_output=True,
                text=True,
                env=_build_kscreen_env(),
                timeout=10
            )

            # Debug: log raw output
            logger.debug(f"kscreen-doctor returncode: {result.returncode}")
            logger.debug(f"kscreen-doctor stdout length: {len(result.stdout)}")
            logger.debug(f"kscreen-doctor stderr: {result.stderr}")
            if result.stdout:
                logger.debug(f"kscreen-doctor first 200 chars: {result.stdout[:200]}")

            if result.returncode != 0:
                logger.error(f"kscreen-doctor failed: {result.stderr}")
                return json.dumps([])

            displays = []
            current = None
            lines = result.stdout.splitlines()

            def _clean_line(line: str) -> str:
                # Remove ANSI escape sequences and stray control chars.
                cleaned = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", line)
                cleaned = cleaned.replace("\x00", "")
                return cleaned.strip()

            for line in lines:
                line_stripped = _clean_line(line)
                if not line_stripped:
                    continue

                # Match "Output: 1 HDMI-A-1 <uuid>" format
                # The name is the third field, enabled/disabled comes on next lines
                match = re.search(r"Output:\s+(\d+)\s+(\S+)", line_stripped)
                if match:
                    if current:
                        displays.append(current)
                    current = {
                        "index": int(match.group(1)),
                        "name": match.group(2),
                        "enabled": True,  # Default, will be updated
                        "resolution": "",
                        "refreshRate": "",
                        "primary": False
                    }
                    continue

                if current:
                    # Check for enabled/disabled on its own line
                    if line_stripped == "enabled":
                        current["enabled"] = True
                    elif line_stripped == "disabled":
                        current["enabled"] = False

                    # Check for priority 1 (primary display)
                    if line_stripped.startswith("priority 1"):
                        current["primary"] = True

                    # Look for current mode (marked with *)
                    # Format: "2:1920x1080@144.00*" or similar
                    if "Modes:" in line_stripped or '@' in line_stripped:
                        # Find pattern like 1920x1080@144.00* (with * at the end)
                        match = re.search(r'(\d+x\d+)@([\d.]+)\*', line_stripped)
                        if match:
                            current["resolution"] = match.group(1)
                            # Take just the integer part of refresh rate
                            refresh = match.group(2)
                            current["refreshRate"] = refresh.split('.')[0]

                    # Check for Geometry line as fallback for resolution
                    if line_stripped.startswith("Geometry:"):
                        match = re.search(r'Geometry:\s+\d+,\d+\s+(\d+x\d+)', line_stripped)
                        if match and not current["resolution"]:
                            current["resolution"] = match.group(1)

            if current:
                displays.append(current)

            logger.info(f"Found {len(displays)} displays: {[d['name'] for d in displays]}")
            return json.dumps(displays)
        except Exception as e:
            logger.error(f"Failed to get displays: {e}")
            return json.dumps([])

    @dbus.service.method(DBUS_INTERFACE, out_signature='s')
    def GetFullStatus(self) -> str:
        """Get full status as JSON for plasmoid"""
        connections = self.connection_monitor.check_connections()
        return json.dumps({
            "state": self.state.name,
            "enabled": self.enabled,
            "remoteActive": self.state == State.REMOTE_ACTIVE,
            "secondaryOutput": self.display_config.secondary_output,
            "rdpConnections": len(connections["rdp"]),
            "vncConnections": len(connections["vnc"])
        })

    # DBus Signals

    @dbus.service.signal(DBUS_INTERFACE, signature='s')
    def StateChanged(self, state: str):
        """Emitted when state changes"""
        pass

    @dbus.service.signal(DBUS_INTERFACE, signature='b')
    def EnabledChanged(self, enabled: bool):
        """Emitted when enabled state changes"""
        pass

    @dbus.service.signal(DBUS_INTERFACE, signature='b')
    def RemoteModeChanged(self, remote_active: bool):
        """Emitted when entering or leaving remote mode"""
        pass


def main():
    """Main entry point"""
    # Ensure state directory exists
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)

    # Set up DBus main loop
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    # Get session bus
    bus = dbus.SessionBus()

    # Check if service is already running
    try:
        bus.get_object(DBUS_SERVICE_NAME, DBUS_OBJECT_PATH)
        logger.error("Service already running")
        sys.exit(1)
    except dbus.exceptions.DBusException:
        pass  # Service not running, continue

    # Register service name
    bus_name = dbus.service.BusName(DBUS_SERVICE_NAME, bus)

    # Create service instance
    service = RdpDisplaySwitcherService(bus_name)

    # Set up signal handlers
    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, shutting down")
        service.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Run main loop
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        service.stop()


if __name__ == "__main__":
    main()
