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
import org.kde.plasma.plasma5support as Plasma5Support
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
    property string keepOutput: "HDMI-A-1"
    property bool scanningDisplays: false
    property string pendingKeepOutput: ""
    property int pendingKeepOutputDeadline: 0

    // File paths for daemon communication
    // The daemon writes status to these files, plasmoid reads them
    readonly property string cacheDir: "/tmp/rdp-display-switcher"
    readonly property string statusFile: cacheDir + "/status.json"
    readonly property string displaysFile: cacheDir + "/displays.json"

    // Display list model
    ListModel {
        id: displayModel
    }

    Plasma5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            if (data) {
                let keys = Object.keys(data)
                if (keys.length > 0) {
                    let parts = []
                    for (let i = 0; i < keys.length; i++) {
                        parts.push(keys[i] + "=" + data[keys[i]])
                    }
                    console.log("Command result: " + sourceName + " -> " + parts.join(", "))
                }
            }
            if (sourceName) {
                disconnectSource(sourceName)
            }
        }
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
        if (!execSource.valid) {
            console.log("Executable data engine not available")
            return
        }
        execSource.connectSource(fullCmd)
    }

    // Refresh status from daemon's status file
    function refreshStatus() {
        let status = readJsonFile(statusFile)
        if (status) {
            root.daemonState = status.state || "IDLE"
            root.daemonEnabled = status.enabled !== false
            root.remoteActive = status.remoteActive || false
            let reportedKeep = status.keepOutput || status.secondaryOutput || "HDMI-A-1"
            if (root.pendingKeepOutput) {
                let now = Date.now()
                if (reportedKeep === root.pendingKeepOutput) {
                    root.pendingKeepOutput = ""
                } else if (now >= root.pendingKeepOutputDeadline) {
                    root.pendingKeepOutput = ""
                }
            }
            if (!root.pendingKeepOutput) {
                root.keepOutput = reportedKeep
            }
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

    // Set output to keep
    function setKeepOutput(outputName) {
        root.keepOutput = outputName
        root.pendingKeepOutput = outputName
        root.pendingKeepOutputDeadline = Date.now() + 4000
        sendCommand("SetKeepOutput", outputName)
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

        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing

        header: PlasmaExtras.PlasmoidHeading {
            leftPadding: Kirigami.Units.largeSpacing
            rightPadding: Kirigami.Units.largeSpacing
            topPadding: Kirigami.Units.smallSpacing
            bottomPadding: Kirigami.Units.smallSpacing

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

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

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
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
                            Kirigami.FormData.label: "Keep enabled:"
                            text: root.keepOutput
                            font.bold: true
                        }
                    }
                }

                ColumnLayout {
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaExtras.Heading {
                        level: 4
                        text: "Controls"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Button {
                            text: "Switch to Remote"
                            icon.name: "computer"
                            enabled: root.daemonRunning && !root.remoteActive && root.daemonState === "IDLE"
                            Layout.fillWidth: true
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            leftPadding: Kirigami.Units.largeSpacing
                            rightPadding: Kirigami.Units.largeSpacing
                            onClicked: switchNow()
                        }

                        PlasmaComponents.Button {
                            text: "Restore Displays"
                            icon.name: "view-restore"
                            enabled: root.daemonRunning && root.remoteActive
                            Layout.fillWidth: true
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            leftPadding: Kirigami.Units.largeSpacing
                            rightPadding: Kirigami.Units.largeSpacing
                            onClicked: restoreNow()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            text: "Auto-switching"
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Switch {
                            checked: root.daemonEnabled
                            enabled: root.daemonRunning
                            onToggled: toggleEnabled()
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            PlasmaExtras.Heading {
                level: 4
                text: "Displays"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

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

                PlasmaComponents.Button {
                    text: "Refresh"
                    icon.name: "view-refresh"
                    flat: true
                    Layout.fillWidth: true
                    onClicked: refreshStatus()
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
                        highlighted: model.name === root.keepOutput

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
                                        visible: model.name === root.keepOutput
                                        text: "Will keep"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: Kirigami.Theme.highlightColor
                                    }
                                }
                            }

                            Kirigami.Icon {
                                visible: model.name === root.keepOutput
                                source: "emblem-checked"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                        }

                        onClicked: {
                            setKeepOutput(model.name)
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

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    visible: !root.daemonRunning
                    text: "Run: systemctl --user start rdp-display-manager"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                }

                Item { Layout.fillWidth: true }
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
    onExpandedChanged: function() {
        if (root.expanded) {
            refreshStatus()
            if (displayModel.count === 0) {
                requestDisplayScan()
            }
        }
    }
}
