/*
 * RDP Display Switcher Plasmoid
 *
 * System tray applet for controlling the RDP Display Switcher daemon.
 *
 * SPDX-License-Identifier: GPL-3.0
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.notification

PlasmoidItem {
    id: root

    // State properties
    property string daemonState: "IDLE"
    property bool daemonEnabled: true
    property bool remoteActive: false
    property int rdpConnections: 0
    property int vncConnections: 0
    property bool daemonRunning: false
    property string secondaryOutput: "HDMI-A-1"

    // DBus interface
    readonly property var dbusService: Qt.createQmlObject(`
        import QtQuick
        import org.kde.plasma.core as PlasmaCore

        PlasmaCore.DataSource {
            engine: "executable"
            connectedSources: []
        }
    `, root)

    // State-dependent icon
    readonly property string stateIcon: {
        if (!daemonRunning) return "network-disconnect"
        if (!daemonEnabled) return "media-playback-paused"
        if (remoteActive) return "network-connect"
        if (daemonState === "DETECTED" || daemonState === "SWITCHING") return "network-wireless-acquiring"
        return "preferences-desktop-remote-desktop"
    }

    // State-dependent tooltip
    readonly property string stateTooltip: {
        if (!daemonRunning) return "Daemon not running"
        if (!daemonEnabled) return "Automatic switching disabled"
        if (remoteActive) return "Remote session active (single display)"
        if (daemonState === "DETECTED") return "Remote connection detected..."
        if (daemonState === "SWITCHING") return "Switching displays..."
        if (daemonState === "RESTORING") return "Restoring displays..."
        return "Monitoring for connections"
    }

    // Plasmoid configuration
    Plasmoid.icon: stateIcon
    toolTipMainText: "RDP Display Switcher"
    toolTipSubText: stateTooltip

    // Prefer representation in system tray
    preferredRepresentation: compactRepresentation

    // Compact representation (system tray icon)
    compactRepresentation: Kirigami.Icon {
        source: root.stateIcon
        active: compactMouseArea.containsMouse

        MouseArea {
            id: compactMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    toggleEnabled()
                } else {
                    root.expanded = !root.expanded
                }
            }
        }

        // Visual indicator for remote mode
        Rectangle {
            visible: root.remoteActive
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.width * 0.4
            height: width
            radius: width / 2
            color: Kirigami.Theme.positiveTextColor

            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.width * 0.7
                height: width
                source: "network-connect"
                color: "white"
            }
        }
    }

    // Full representation (popup)
    fullRepresentation: PlasmaExtras.Representation {
        id: fullRep

        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent

                Kirigami.Icon {
                    source: root.stateIcon
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaExtras.Heading {
                        level: 3
                        text: "RDP Display Switcher"
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        text: root.stateTooltip
                        opacity: 0.7
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        Layout.fillWidth: true
                    }
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            // Status section
            PlasmaExtras.Heading {
                level: 4
                text: "Status"
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    Kirigami.FormData.label: "Daemon:"
                    text: root.daemonRunning ? "Running" : "Not running"
                    color: root.daemonRunning ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                }

                PlasmaComponents.Label {
                    Kirigami.FormData.label: "State:"
                    text: root.daemonState
                }

                PlasmaComponents.Label {
                    Kirigami.FormData.label: "Display mode:"
                    text: root.remoteActive ? "Single (Remote)" : "Extended (Normal)"
                    color: root.remoteActive ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                }

                PlasmaComponents.Label {
                    Kirigami.FormData.label: "Connections:"
                    text: {
                        let parts = []
                        if (root.rdpConnections > 0) parts.push(`${root.rdpConnections} RDP`)
                        if (root.vncConnections > 0) parts.push(`${root.vncConnections} VNC`)
                        return parts.length > 0 ? parts.join(", ") : "None"
                    }
                }

                PlasmaComponents.Label {
                    Kirigami.FormData.label: "Secondary:"
                    text: root.secondaryOutput
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // Controls section
            PlasmaExtras.Heading {
                level: 4
                text: "Controls"
            }

            // Enable/disable toggle
            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: "Automatic switching"
                    Layout.fillWidth: true
                }

                PlasmaComponents.Switch {
                    id: enableSwitch
                    checked: root.daemonEnabled
                    enabled: root.daemonRunning
                    onToggled: toggleEnabled()
                }
            }

            // Manual control buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Button {
                    text: "Switch to Remote"
                    icon.name: "monitor"
                    enabled: root.daemonRunning && !root.remoteActive && root.daemonState === "IDLE"
                    Layout.fillWidth: true
                    onClicked: switchNow()
                }

                PlasmaComponents.Button {
                    text: "Restore Displays"
                    icon.name: "view-restore"
                    enabled: root.daemonRunning && root.remoteActive
                    Layout.fillWidth: true
                    onClicked: restoreNow()
                }
            }

            Item { Layout.fillHeight: true }

            // Footer with daemon control
            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    text: root.daemonRunning ? "Restart Daemon" : "Start Daemon"
                    icon.name: "system-reboot"
                    flat: true
                    onClicked: restartDaemon()
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Button {
                    text: "Configure..."
                    icon.name: "configure"
                    flat: true
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
            }
        }
    }

    // DBus calls using qdbus command execution
    function callDbus(method: string, args: string = "") {
        let cmd = `qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher org.kde.rdpdisplayswitcher.${method}`
        if (args) cmd += ` ${args}`
        dbusService.connectSource(cmd)
    }

    function toggleEnabled() {
        callDbus("SetEnabled", root.daemonEnabled ? "false" : "true")
        root.daemonEnabled = !root.daemonEnabled
    }

    function switchNow() {
        callDbus("SwitchNow")
    }

    function restoreNow() {
        callDbus("RestoreNow")
    }

    function restartDaemon() {
        dbusService.connectSource("systemctl --user restart rdp-display-manager")
    }

    function refreshStatus() {
        // Check if daemon is running
        dbusService.connectSource("qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher org.kde.rdpdisplayswitcher.GetState 2>/dev/null || echo 'DAEMON_NOT_RUNNING'")
    }

    // Handle command execution results
    Connections {
        target: dbusService
        function onNewData(sourceName, data) {
            let output = data.stdout ? data.stdout.trim() : ""

            if (sourceName.includes("GetState")) {
                if (output === "DAEMON_NOT_RUNNING" || output === "") {
                    root.daemonRunning = false
                } else {
                    root.daemonRunning = true
                    root.daemonState = output
                    root.remoteActive = (output === "REMOTE_ACTIVE")
                }
            }

            // Clean up completed sources
            dbusService.disconnectSource(sourceName)
        }
    }

    // Notification helper
    Notification {
        id: notification
        componentName: "rdpdisplayswitcher"
        eventId: "stateChange"
    }

    function showNotification(title: string, message: string) {
        notification.title = title
        notification.text = message
        notification.sendEvent()
    }

    // Timer for periodic status updates
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: refreshStatus()
    }

    // Initial status check
    Component.onCompleted: {
        refreshStatus()
    }

    // DBus signal monitoring using a DataSource
    PlasmaCore.DataSource {
        id: dbusMonitor
        engine: "executable"

        // Monitor for state changes via dbus-monitor (lightweight approach)
        connectedSources: [
            "dbus-monitor --session \"type='signal',interface='org.kde.rdpdisplayswitcher'\" 2>/dev/null | head -1"
        ]

        interval: 0

        onNewData: (sourceName, data) => {
            // When we receive a signal, refresh our status
            if (data.stdout) {
                refreshStatus()
            }
        }
    }
}
