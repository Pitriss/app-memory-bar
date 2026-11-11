import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Applications")
        icon: "applications-system"
        source: "configApps.qml"
    }

    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-theme"
        source: "configGeneral.qml"
    }
}
