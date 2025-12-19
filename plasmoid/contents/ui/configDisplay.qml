/*
 * Display configuration page for RDP Display Switcher
 * SPDX-License-Identifier: GPL-3.0
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configDisplay

    property alias cfg_secondaryOutput: secondaryOutputField.text

    Kirigami.FormLayout {
        anchors.fill: parent

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Display Configuration")
        }

        QQC2.TextField {
            id: secondaryOutputField
            Kirigami.FormData.label: i18n("Secondary display:")
            placeholderText: "HDMI-A-1"
        }

        QQC2.Label {
            text: i18n("The display output name that will be disabled during remote sessions.\nCommon names: HDMI-A-1, HDMI-A-2, DP-1, DP-2, DP-3")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("How to find your display names")
        }

        QQC2.Label {
            text: i18n("Run this command in a terminal to see your display outputs:\n\nkscreen-doctor -o\n\nLook for lines starting with 'Output:' followed by the display name.")
            font.family: "monospace"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }
}
