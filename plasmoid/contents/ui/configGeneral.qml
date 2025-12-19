/*
 * General configuration page for RDP Display Switcher
 *
 * SPDX-License-Identifier: GPL-3.0
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configGeneral

    property alias cfg_rdpPorts: rdpPortsField.text
    property alias cfg_vncPorts: vncPortsField.text
    property alias cfg_debounceTime: debounceSpinBox.value
    property alias cfg_showNotifications: notificationsCheck.checked
    property alias cfg_autoStart: autoStartCheck.checked

    Kirigami.FormLayout {
        anchors.fill: parent

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Connection Monitoring")
        }

        QQC2.TextField {
            id: rdpPortsField
            Kirigami.FormData.label: i18n("RDP ports:")
            placeholderText: "3389"
        }

        QQC2.TextField {
            id: vncPortsField
            Kirigami.FormData.label: i18n("VNC ports:")
            placeholderText: "5900,5901,5902"
        }

        QQC2.SpinBox {
            id: debounceSpinBox
            Kirigami.FormData.label: i18n("Debounce time (seconds):")
            from: 1
            to: 30
            stepSize: 1
        }

        QQC2.Label {
            text: i18n("Time to wait before switching displays after connection detected")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Behavior")
        }

        QQC2.CheckBox {
            id: notificationsCheck
            Kirigami.FormData.label: i18n("Show notifications:")
            text: i18n("Notify on display mode changes")
        }

        QQC2.CheckBox {
            id: autoStartCheck
            Kirigami.FormData.label: i18n("Auto-start:")
            text: i18n("Start daemon with Plasma session")
        }
    }
}
