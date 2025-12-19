/*
 * RDP Display Switcher Plasmoid
 * System tray applet for controlling the RDP Display Switcher daemon.
 * SPDX-License-Identifier: GPL-3.0
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

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

    // File paths for daemon communication
    // The daemon writes status to these files, plasmoid reads them
    readonly property string cacheDir: "/tmp/rdp-display-switcher"
    readonly property string statusFile: cacheDir + "/status.json"
    readonly property string displaysFile: cacheDir + "/displays.json"

    // Display list model
    ListModel {
        id: displayModel
    }

    // Read JSON file helper
    function readJsonFile(filePath) {
        let xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + filePath, false)
        try {
            xhr.send()
            if (xhr.status === 200 && xhr.responseText) {
                return JSON.parse(xhr.responseText)
            }
        } catch (e) {
            // File doesn't exist or parse error
        }
        return null
    }

    // Write command to file (daemon watches this)
    function sendCommand(cmd, args) {
        // Commands are sent via qdbus in background
        let fullCmd = "qdbus org.kde.rdpdisplayswitcher /org/kde/rdpdisplayswitcher org.kde.rdpdisplayswitcher." + cmd
        if (args !== undefined) {
            fullCmd += " " + args
        }
        console.log("Sending command: " + fullCmd)
        // We'll trigger this via the daemon's file watcher or periodic check
    }

    // Refresh status from daemon's status file
    function refreshStatus() {
        let status = readJsonFile(statusFile)
        if (status) {
            root.daemonState = status.state || "IDLE"
            root.daemonEnabled = status.enabled !== false
            root.remoteActive = status.remoteActive || false
            root.secondaryOutput = status.secondaryOutput || "HDMI-A-1"
            root.rdpConnections = status.rdpConnections || 0
            root.vncConnections = status.vncConnections || 0
            root.daemonRunning = true
        } else {
            root.daemonRunning = false
        }
    }

    // Scan displays
    function scanDisplays() {
        root.scanningDisplays = true

        let displays = readJsonFile(displaysFile)
        if (displays && Array.isArray(displays)) {
            displayModel.clear()
            for (let i = 0; i < displays.length; i++) {
                displayModel.append(displays[i])
            }
            console.log("Loaded " + displays.length + " displays from file")
        }

        root.scanningDisplays = false
    }

    // Set secondary output
    function setSecondaryOutput(outputName) {
        root.secondaryOutput = outputName
        sendCommand("SetSecondaryOutput", '"' + outputName + '"')
    }

    // Toggle enabled state
    function toggleEnabled() {
        let newState = !root.daemonEnabled
        root.daemonEnabled = newState
        sendCommand("SetEnabled", newState ? "true" : "false")
    }

    // Manual switch to remote mode
    function switchNow() {
        sendCommand("SwitchNow")
    }

    // Manual restore
    function restoreNow() {
        sendCommand("RestoreNow")
    }

    // Request display scan from daemon
    function requestDisplayScan() {
        sendCommand("GetDisplays")
        // Wait a moment then read the file
        scanTimer.start()
    }

    Timer {
        id: scanTimer
        interval: 500
        repeat: false
        onTriggered: scanDisplays()
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

    Plasmoid.icon: stateIcon
    toolTipMainText: "RDP Display Switcher"
    toolTipSubText: stateTooltip
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
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24

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
                        if (root.rdpConnections > 0) parts.push(root.rdpConnections + " RDP")
                        if (root.vncConnections > 0) parts.push(root.vncConnections + " VNC")
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

            PlasmaExtras.Heading {
                level: 4
                text: "Displays"
            }

            PlasmaComponents.Button {
                text: root.scanningDisplays ? "Scanning..." : "Scan Displays"
                icon.name: "view-refresh"
                enabled: !root.scanningDisplays
                Layout.fillWidth: true
                onClicked: {
                    root.scanningDisplays = true
                    requestDisplayScan()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: displayModel.count > 0

                Repeater {
                    model: displayModel

                    delegate: PlasmaComponents.ItemDelegate {
                        Layout.fillWidth: true
                        highlighted: model.name === root.secondaryOutput

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: "video-display"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
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
                                        text: model.resolution ? "(" + model.resolution + ")" : ""
                                        opacity: 0.8
                                    }

                                    PlasmaComponents.Label {
                                        visible: model.refreshRate && model.refreshRate !== ""
                                        text: "@ " + model.refreshRate + "Hz"
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
                                        visible: model.enabled === false
                                        text: "Disabled"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: Kirigami.Theme.neutralTextColor
                                    }

                                    PlasmaComponents.Label {
                                        visible: model.name === root.secondaryOutput
                                        text: "Selected for remote"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: Kirigami.Theme.highlightColor
                                    }
                                }
                            }

                            Kirigami.Icon {
                                visible: model.name === root.secondaryOutput
                                source: "emblem-checked"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                        }

                        onClicked: {
                            setSecondaryOutput(model.name)
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                visible: displayModel.count === 0
                text: "Click 'Scan Displays' to detect monitors"
                opacity: 0.6
                font.italic: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            PlasmaExtras.Heading {
                level: 4
                text: "Controls"
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: "Automatic switching"
                    Layout.fillWidth: true
                }

                PlasmaComponents.Switch {
                    checked: root.daemonEnabled
                    enabled: root.daemonRunning
                    onToggled: toggleEnabled()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Button {
                    text: "Switch to Remote"
                    icon.name: "computer"
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

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    text: "Start Daemon"
                    icon.name: "system-run"
                    visible: !root.daemonRunning
                    flat: true
                    onClicked: {
                        // Try to start via systemctl
                        console.log("Starting daemon...")
                    }
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Button {
                    text: "Refresh"
                    icon.name: "view-refresh"
                    flat: true
                    onClicked: refreshStatus()
                }
            }
        }
    }

    // Periodic status refresh
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: refreshStatus()
    }

    // Initial setup
    Component.onCompleted: {
        refreshStatus()
    }

    // Refresh when popup opens
    onExpandedChanged: {
        if (expanded) {
            refreshStatus()
            if (displayModel.count === 0) {
                requestDisplayScan()
            }
        }
    }
}
