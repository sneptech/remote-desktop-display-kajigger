/*
 * Display configuration page for RDP Display Switcher
 *
 * SPDX-License-Identifier: GPL-3.0
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support

KCM.SimpleKCM {
    id: configDisplay

    property alias cfg_secondaryOutput: secondaryOutputCombo.editText
    property var availableOutputs: []

    // Fetch available outputs on load
    Plasma5Support.DataSource {
        id: outputsSource
        engine: "executable"
        connectedSources: ["kscreen-doctor -o 2>/dev/null | grep 'Output:' | awk '{print $2}'"]

        onNewData: (sourceName, data) => {
            if (data.stdout) {
                let outputs = data.stdout.trim().split('\n').filter(o => o.length > 0)
                configDisplay.availableOutputs = outputs
            }
        }
    }

    Kirigami.FormLayout {
        anchors.fill: parent

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Display Configuration")
        }

        QQC2.ComboBox {
            id: secondaryOutputCombo
            Kirigami.FormData.label: i18n("Secondary display:")
            editable: true
            model: configDisplay.availableOutputs.length > 0 ? configDisplay.availableOutputs : ["HDMI-A-1", "HDMI-A-2", "DP-2", "DP-3"]

            Component.onCompleted: {
                // Set current value
                if (cfg_secondaryOutput) {
                    let idx = find(cfg_secondaryOutput)
                    if (idx >= 0) {
                        currentIndex = idx
                    } else {
                        editText = cfg_secondaryOutput
                    }
                }
            }
        }

        QQC2.Label {
            text: i18n("The display that will be disabled during remote sessions")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Current Configuration")
        }

        // Show current display configuration
        Repeater {
            model: configDisplay.availableOutputs

            delegate: RowLayout {
                Kirigami.FormData.label: modelData === cfg_secondaryOutput ? i18n("Secondary:") : i18n("Output:")
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: modelData
                    font.bold: modelData === cfg_secondaryOutput
                }

                QQC2.Label {
                    text: modelData === cfg_secondaryOutput ? i18n("(will be disabled)") : ""
                    opacity: 0.7
                    font.italic: true
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
            height: Kirigami.Units.largeSpacing
        }

        QQC2.Button {
            text: i18n("Refresh Outputs")
            icon.name: "view-refresh"
            onClicked: {
                outputsSource.disconnectSource(outputsSource.connectedSources[0])
                outputsSource.connectSource("kscreen-doctor -o 2>/dev/null | grep 'Output:' | awk '{print $2}'")
            }
        }
    }
}
