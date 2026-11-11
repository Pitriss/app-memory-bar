import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    width: 360
    height: 104

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property real backgroundAlpha: Math.max(0, Math.min(1, 1 - plasmoid.configuration.backgroundTransparency / 100.0))
    readonly property real barCornerRadius: Math.max(0, plasmoid.configuration.barRadius)
    readonly property real backgroundCornerRadius: Math.max(0, plasmoid.configuration.backgroundRadius)
    readonly property real contentPadding: Math.max(0, plasmoid.configuration.contentPadding)

    readonly property bool customFont: plasmoid.configuration.fontFamily.length > 0
    readonly property string configuredFontFamily: customFont ? plasmoid.configuration.fontFamily : Qt.application.font.family
    readonly property real configuredFontPointSize: customFont && plasmoid.configuration.fontPointSize > 0 ? plasmoid.configuration.fontPointSize : Qt.application.font.pointSize
    readonly property int configuredFontWeight: customFont && plasmoid.configuration.fontWeight > 0 ? plasmoid.configuration.fontWeight : Qt.application.font.weight
    readonly property bool configuredFontItalic: customFont ? plasmoid.configuration.fontItalic : Qt.application.font.italic
    readonly property bool configuredFontUnderline: customFont ? plasmoid.configuration.fontUnderline : Qt.application.font.underline
    readonly property bool configuredFontStrikeout: customFont ? plasmoid.configuration.fontStrikeout : Qt.application.font.strikeout
    readonly property string configuredFontStyleName: customFont ? plasmoid.configuration.fontStyleName : Qt.application.font.styleName
    readonly property real smallFontPointSize: Math.max(6, configuredFontPointSize * 0.82)

    readonly property color widgetBackgroundColor: plasmoid.configuration.backgroundColor.length > 0
        ? plasmoid.configuration.backgroundColor
        : Kirigami.Theme.backgroundColor
    readonly property color trackBackgroundColor: plasmoid.configuration.barTrackColor.length > 0
        ? plasmoid.configuration.barTrackColor
        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)

    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/app-memory-probe.sh").toString().replace("file://", ""))
    readonly property string targetScopePrefix: plasmoid.configuration.targetScopePrefix
    readonly property string targetExecutable: plasmoid.configuration.targetExecutable
    readonly property string configuredDisplayName: plasmoid.configuration.targetDisplayName
    readonly property bool maintainLimitsByExecutable: plasmoid.configuration.maintainLimitsByExecutable
    readonly property double desiredHighBytes: Number(plasmoid.configuration.desiredHighBytes)
    readonly property double desiredMaxBytes: Number(plasmoid.configuration.desiredMaxBytes)
    readonly property bool desiredLimitsValid: desiredHighBytes > 0 && desiredMaxBytes > desiredHighBytes

    property string runtimeDisplayName: ""
    property string runtimeUnits: ""
    property string runtimeExecutable: ""
    property string runtimeProcesses: ""
    property int runtimeUnitCount: 0
    property string enforcementState: "off"

    property bool appRunning: false
    property bool limitsValid: false
    property double currentBytes: 0
    property double highBytes: 0
    property double maxBytes: 0

    readonly property double gib: 1073741824
    // A multi-unit app can have a real aggregate MemoryHigh while no shared
    // kernel MemoryMax exists.  Use the configured hard target as the visual
    // ceiling when available; otherwise scale the bar to MemoryHigh itself.
    readonly property bool hardLimitValid: limitsValid && isFinite(maxBytes) && maxBytes > highBytes
    readonly property bool visualTargetValid: limitsValid && desiredLimitsValid && desiredMaxBytes > highBytes
    readonly property double visualMaxBytes: hardLimitValid
        ? maxBytes
        : visualTargetValid
            ? desiredMaxBytes
            : limitsValid
                ? highBytes
                : 0
    readonly property bool hasExtendedRange: limitsValid && visualMaxBytes > highBytes
    readonly property double usageFraction: limitsValid && visualMaxBytes > 0
        ? Math.max(0, Math.min(1, currentBytes / visualMaxBytes))
        : 0
    readonly property double highFraction: limitsValid && visualMaxBytes > 0
        ? Math.max(0, Math.min(1, highBytes / visualMaxBytes))
        : 0
    readonly property double redThresholdBytes: hasExtendedRange
        ? Math.max(highBytes, visualMaxBytes * 0.90)
        : 1.0e30

    readonly property color okColor: plasmoid.configuration.okColor
    readonly property color warningColor: plasmoid.configuration.warningColor
    readonly property color dangerColor: plasmoid.configuration.dangerColor
    readonly property color inactiveColor: Kirigami.Theme.disabledTextColor

    readonly property color stateColor: !appRunning || !limitsValid
        ? inactiveColor
        : hasExtendedRange && currentBytes >= redThresholdBytes
            ? dangerColor
            : currentBytes >= highBytes
                ? warningColor
                : okColor

    readonly property string applicationName: {
        const raw = appRunning && runtimeDisplayName.length > 0
            ? runtimeDisplayName
            : configuredDisplayName.length > 0
                ? configuredDisplayName
                : targetExecutable.length > 0
                    ? targetExecutable.split("/").pop()
                    : "App"
        return prettyName(raw)
    }

    readonly property string probeCommand: "sh " + shellQuote(helperPath) + " probe-target " + shellQuote(targetExecutable)
        + " " + shellQuote(targetScopePrefix) + " " + shellQuote(configuredDisplayName)
        + " " + (maintainLimitsByExecutable && desiredLimitsValid ? "1" : "0")
        + " " + Math.round(desiredHighBytes) + " " + Math.round(desiredMaxBytes)

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function prettyName(name) {
        const value = String(name || "").trim()
        if (value.length === 0) return "App"
        return value.charAt(0).toUpperCase() + value.slice(1)
    }

    function formatGiB(bytes) {
        if (!isFinite(bytes) || bytes < 0) return "?"
        return (bytes / gib).toFixed(1) + " GiB"
    }

    function resetValues() {
        currentBytes = 0
        highBytes = 0
        maxBytes = 0
        runtimeDisplayName = ""
        runtimeUnits = ""
        runtimeExecutable = ""
        runtimeProcesses = ""
        runtimeUnitCount = 0
        enforcementState = "off"
    }

    function parseProbe(output) {
        const line = String(output || "").trim()
        const fields = line.split("\t")
        if (fields[0] === "STOPPED") {
            appRunning = false
            limitsValid = false
            resetValues()
            return
        }
        if (fields.length < 10 || fields[0] !== "RUNNING") {
            appRunning = false
            limitsValid = false
            resetValues()
            return
        }

        appRunning = true
        currentBytes = Number(fields[1])
        highBytes = fields[2] === "max" ? 0 : Number(fields[2])
        maxBytes = fields[3] === "max" ? 0 : Number(fields[3])
        runtimeDisplayName = fields[4]
        runtimeUnitCount = Number(fields[5]) || 0
        runtimeUnits = fields[6]
        runtimeExecutable = fields[7]
        runtimeProcesses = fields[8]
        enforcementState = fields[9]
        // MemoryHigh alone is already a meaningful limit.  Multi-unit apps
        // intentionally report MemoryMax=max because no common sibling hard
        // cap exists.
        limitsValid = isFinite(currentBytes) && isFinite(highBytes) && highBytes > 0
    }

    toolTipMainText: i18n("%1 Memory", applicationName)
    toolTipSubText: !appRunning
        ? i18n("%1 is not running", applicationName)
        : limitsValid
            ? formatGiB(currentBytes) + " / HIGH " + formatGiB(highBytes)
                + (hardLimitValid
                    ? " / MAX " + formatGiB(maxBytes)
                    : visualTargetValid
                        ? " / TARGET " + formatGiB(desiredMaxBytes) + " (" + i18n("HARD not enforced") + ")"
                        : " / " + i18n("HARD unlimited"))
                + " / " + i18np("%1 unit", "%1 units", runtimeUnitCount)
                + (enforcementState === "pending-max" ? " / " + i18n("HARD waiting for RAM to drop") : "")
            : formatGiB(currentBytes) + " / " + i18n("without MemoryHigh") + " / " + i18np("%1 unit", "%1 units", runtimeUnitCount)

    Plasma5Support.DataSource {
        id: probe
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (sourceName !== root.probeCommand) return
            root.parseProbe(data["stdout"] || "")
        }

        function refresh() {
            if (root.targetExecutable.length === 0 && root.configuredDisplayName.length === 0) return
            if (connectedSources.indexOf(root.probeCommand) === -1) connectSource(root.probeCommand)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: probe.refresh()
    }

    fullRepresentation: Item {
        implicitWidth: 360
        implicitHeight: 104

        Rectangle {
            anchors.fill: parent
            radius: root.backgroundCornerRadius
            color: Qt.rgba(root.widgetBackgroundColor.r, root.widgetBackgroundColor.g, root.widgetBackgroundColor.b, root.backgroundAlpha)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
        }

        Item {
            id: contentViewport
            x: root.contentPadding
            y: root.contentPadding
            width: Math.max(0, parent.width - root.contentPadding * 2)
            height: Math.max(0, parent.height - root.contentPadding * 2)

            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        text: root.applicationName + " RAM"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family: root.configuredFontFamily
                        font.pointSize: root.configuredFontPointSize
                        font.weight: root.configuredFontWeight
                        font.italic: root.configuredFontItalic
                        font.underline: root.configuredFontUnderline
                        font.strikeout: root.configuredFontStrikeout
                        font.styleName: root.configuredFontStyleName
                    }

                    PlasmaComponents.Label {
                        text: !root.appRunning
                            ? i18n("stopped")
                            : root.limitsValid
                                ? root.formatGiB(root.currentBytes)
                                : root.formatGiB(root.currentBytes)
                        color: root.stateColor
                        font.family: root.configuredFontFamily
                        font.pointSize: root.configuredFontPointSize
                        font.weight: root.configuredFontWeight
                        font.italic: root.configuredFontItalic
                        font.underline: root.configuredFontUnderline
                        font.strikeout: root.configuredFontStrikeout
                        font.styleName: root.configuredFontStyleName
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22

                    Rectangle {
                        id: track
                        anchors.fill: parent
                        radius: root.barCornerRadius
                        color: root.trackBackgroundColor
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.24)
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: root.appRunning && root.limitsValid ? parent.width * root.usageFraction : 0
                            radius: parent.radius
                            color: root.stateColor

                            Behavior on width { NumberAnimation { duration: 220 } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }

                        Rectangle {
                            visible: root.appRunning && root.limitsValid
                            x: Math.max(1, Math.min(track.width - width - 1, track.width * root.highFraction - width / 2))
                            width: 3
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            color: Kirigami.Theme.textColor
                            opacity: 0.9
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(18, root.smallFontPointSize * 1.8)

                    PlasmaComponents.Label {
                        visible: root.appRunning && root.limitsValid
                        text: "▲ HIGH " + root.formatGiB(root.highBytes)
                        color: Kirigami.Theme.textColor
                        x: Math.max(0, Math.min(parent.width - width, parent.width * root.highFraction - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: root.configuredFontFamily
                        font.pointSize: root.smallFontPointSize
                        font.weight: root.configuredFontWeight
                        font.italic: root.configuredFontItalic
                        font.underline: root.configuredFontUnderline
                        font.strikeout: root.configuredFontStrikeout
                        font.styleName: root.configuredFontStyleName
                    }

                    PlasmaComponents.Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: !root.appRunning
                            ? i18n("%1 is not running", root.applicationName)
                            : root.limitsValid
                                ? root.hardLimitValid
                                    ? "MAX " + root.formatGiB(root.maxBytes)
                                    : root.visualTargetValid
                                        ? "TARGET " + root.formatGiB(root.desiredMaxBytes) + " · " + i18np("%1 unit", "%1 units", root.runtimeUnitCount)
                                        : i18n("HARD unlimited") + " · " + i18np("%1 unit", "%1 units", root.runtimeUnitCount)
                                : i18n("without MemoryHigh") + " · " + i18np("%1 unit", "%1 units", root.runtimeUnitCount)
                        color: root.appRunning && !root.limitsValid ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.disabledTextColor
                        font.family: root.configuredFontFamily
                        font.pointSize: root.smallFontPointSize
                        font.weight: root.configuredFontWeight
                        font.italic: root.configuredFontItalic
                        font.underline: root.configuredFontUnderline
                        font.strikeout: root.configuredFontStrikeout
                        font.styleName: root.configuredFontStyleName
                    }
                }
            }
        }
    }
}
