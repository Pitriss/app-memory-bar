import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Aplikace")
        icon: "applications-system"
        source: "configApps.qml"
    }

    ConfigCategory {
        name: i18n("Vzhled")
        icon: "preferences-desktop-theme"
        source: "configGeneral.qml"
    }
}
