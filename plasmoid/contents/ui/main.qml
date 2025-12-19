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
    property bool scanningDisplays: false

    // Display list model
    ListModel {
        id: displayModel
    }

    // DBus/command execution interface
    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            let stdout = data.stdout ? data.stdout.trim() : ""
            let stderr = data.stderr ? data.stderr.trim() : ""

            // Handle kscreen-doctor output for display scanning
            if (sourceName.includes("kscreen-doctor -o")) {
                parseDisplayOutput(stdout)
                root.scanningDisplays = false
            }
            // Handle daemon state check
            else if (sourceName.includes("GetState")) {
                if (stdout === "DAEMON_NOT_RUNNING" || stdout === "") {
                    root.daemonRunning = false
                } else {
                    root.daemonRunning = true
                    root.daemonState = stdout
                    root.remoteActive = (stdout === "REMOTE_ACTIVE")
                }
            }

            // Clean up completed sources
            disconnectSource(sourceName)
        }
    }

    // Parse kscreen-doctor -o output
    function parseDisplayOutput(output: string) {
        displayModel.clear()

        let lines = output.split('\n')
        let currentOutput = null

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim()

            // Match "Output: N DP-1 enabled" or similar
            let outputMatch = line.match(/^Output:\s+(\d+)\s+(\S+)\s+(enabled|disabled)/)
            if (outputMatch) {
                if (currentOutput) {
                    displayModel.append(currentOutput)
                }
                currentOutput = {
                    index: parseInt(outputMatch[1]),
                    name: outputMatch[2],
                    enabled: outputMatch[3] === "enabled",
                    resolution: "",
                    refreshRate: "",
                    position: "",
                    primary: false
                }
                continue
            }

            // If we have a current output, look for its properties
            if (currentOutput) {
                // Match resolution like "Modes: 2560x1440@144* ..." (the * indicates current)
                let modeMatch = line.match(/(\d+x\d+)@(\d+)\*/)
                if (modeMatch) {
                    currentOutput.resolution = modeMatch[1]
                    currentOutput.refreshRate = modeMatch[2]
                }

                // Match "Geometry: 0,0 2560x1440"
                let geoMatch = line.match(/Geometry:\s+(\d+),(\d+)\s+(\d+x\d+)/)
                if (geoMatch) {
                    currentOutput.position = `${geoMatch[1]},${geoMatch[2]}`
                    if (!currentOutput.resolution) {
                        currentOutput.resolution = geoMatch[3]
                    }
                }

                // Check for primary
                if (line.includes("primary")) {
                    currentOutput.primary = true
                }
            }
        }

        // Don't forget the last output
        if (currentOutput) {
            displayModel.append(currentOutput)
        }

        console.log("Parsed " + displayModel.count + " displays")
    }

    // Scan for displays
    function scanDisplays() {
        root.scanningDisplays = true
        executable.connectSource("kscreen-doctor -o 2>/dev/null")
    }

    // Set secondary output via daemon
    function setSecondaryOutput(outputName: string) {
        root.secondaryOutput = outputName
        let cmd = `qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher org.kde.rdpdisplayswitcher.SetSecondaryOutput "${outputName}"`
        executable.connectSource(cmd)
    }

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

        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 22

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
                    font.bold: true
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // Displays section
            PlasmaExtras.Heading {
                level: 4
                text: "Displays"
            }

            // Scan button
            PlasmaComponents.Button {
                text: root.scanningDisplays ? "Scanning..." : "Scan Displays"
                icon.name: root.scanningDisplays ? "view-refresh" : "monitor"
                enabled: !root.scanningDisplays
                Layout.fillWidth: true
                onClicked: scanDisplays()

                // Spinning animation when scanning
                Kirigami.Icon {
                    visible: root.scanningDisplays
                    source: "view-refresh"
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.iconSizes.small
                    height: width

                    RotationAnimation on rotation {
                        running: root.scanningDisplays
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }
            }

            // Display list
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: displayModel.count > 0

                Repeater {
                    model: displayModel

                    delegate: PlasmaComponents.Button {
                        Layout.fillWidth: true

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: model.primary ? "monitor-symbolic" : "video-display"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                color: model.name === root.secondaryOutput ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        text: model.name
                                        font.bold: true
                                    }

                                    PlasmaComponents.Label {
                                        text: model.resolution ? `(${model.resolution})` : ""
                                        opacity: 0.8
                                    }

                                    PlasmaComponents.Label {
                                        visible: model.refreshRate !== ""
                                        text: `@ ${model.refreshRate}Hz`
                                        opacity: 0.6
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        visible: model.primary
                                        text: "Primary"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: Kirigami.Theme.positiveTextColor
                                    }

                                    PlasmaComponents.Label {
                                        visible: !model.enabled
                                        text: "Disabled"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: Kirigami.Theme.neutralTextColor
                                    }

                                    PlasmaComponents.Label {
                                        visible: model.name === root.secondaryOutput
                                        text: "Will disable for remote"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: Kirigami.Theme.negativeTextColor
                                    }
                                }
                            }

                            // Checkmark for selected secondary
                            Kirigami.Icon {
                                visible: model.name === root.secondaryOutput
                                source: "checkbox"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                color: Kirigami.Theme.negativeTextColor
                            }
                        }

                        onClicked: {
                            setSecondaryOutput(model.name)
                        }

                        // Highlight current secondary selection
                        highlighted: model.name === root.secondaryOutput
                    }
                }
            }

            // Hint when no displays scanned
            PlasmaComponents.Label {
                visible: displayModel.count === 0
                text: "Click 'Scan Displays' to detect connected monitors"
                opacity: 0.6
                font.italic: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
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
        executable.connectSource(cmd)
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
        executable.connectSource("systemctl --user restart rdp-display-manager")
    }

    function refreshStatus() {
        // Check if daemon is running
        executable.connectSource("qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher org.kde.rdpdisplayswitcher.GetState 2>/dev/null || echo 'DAEMON_NOT_RUNNING'")
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

    // Initial status check and display scan
    Component.onCompleted: {
        refreshStatus()
        // Auto-scan displays on first open
        scanDisplays()
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
