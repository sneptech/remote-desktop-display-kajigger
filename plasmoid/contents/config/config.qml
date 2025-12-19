/*
 * Configuration page for RDP Display Switcher
 *
 * SPDX-License-Identifier: GPL-3.0
 */

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "preferences-desktop-remote-desktop"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Display")
        icon: "preferences-desktop-display"
        source: "configDisplay.qml"
    }
}
