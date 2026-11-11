import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQControls
import org.kde.plasma.plasma5support as Plasma5Support

QQC2.ScrollView {
    id: page
    clip: true
    contentWidth: availableWidth
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
    QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded

    // Keep cfg_* as real top-level properties. Plasma watches their notify
    // signals to enable Apply/Reset; using Slider.value aliases proved
    // unreliable on some Plasma 6 versions.
    property int cfg_backgroundTransparency: 28
    property int cfg_barRadius: 11
    property int cfg_backgroundRadius: 11
    property int cfg_contentPadding: 6

    property string cfg_fontFamily: ""
    property real cfg_fontPointSize: 0
    property int cfg_fontWeight: 400
    property bool cfg_fontItalic: false
    property bool cfg_fontUnderline: false
    property bool cfg_fontStrikeout: false
    property string cfg_fontStyleName: ""

    property string cfg_backgroundColor: ""
    property string cfg_barTrackColor: ""
    property color cfg_okColor: "#35b86b"
    property color cfg_warningColor: "#e3a008"
    property color cfg_dangerColor: "#d83b3b"

    readonly property bool usingSystemFont: cfg_fontFamily.length === 0
    readonly property font effectiveFont: ({
        family: usingSystemFont ? Qt.application.font.family : cfg_fontFamily,
        pointSize: usingSystemFont || cfg_fontPointSize <= 0 ? Qt.application.font.pointSize : cfg_fontPointSize,
        weight: usingSystemFont || cfg_fontWeight <= 0 ? Qt.application.font.weight : cfg_fontWeight,
        italic: usingSystemFont ? Qt.application.font.italic : cfg_fontItalic,
        underline: usingSystemFont ? Qt.application.font.underline : cfg_fontUnderline,
        strikeout: usingSystemFont ? Qt.application.font.strikeout : cfg_fontStrikeout,
        styleName: usingSystemFont ? Qt.application.font.styleName : cfg_fontStyleName
    })

    function fontSummary() {
        if (usingSystemFont) {
            return i18n("System font")
        }

        let details = cfg_fontFamily + "  " + Number(cfg_fontPointSize).toFixed(1) + " pt"
        if (cfg_fontStyleName.length > 0) {
            details += "  " + cfg_fontStyleName
        } else {
            details += "  " + i18n("weight %1", cfg_fontWeight)
        }
        return details
    }

    function openFontDialog() {
        fontDialog.currentFont = effectiveFont
        fontDialog.open()
    }

    function setSystemFont() {
        cfg_fontFamily = ""
        cfg_fontPointSize = 0
        cfg_fontWeight = 400
        cfg_fontItalic = false
        cfg_fontUnderline = false
        cfg_fontStrikeout = false
        cfg_fontStyleName = ""
    }

    function backgroundPreviewColor() {
        return cfg_backgroundColor.length > 0 ? cfg_backgroundColor : Kirigami.Theme.backgroundColor
    }

    function trackPreviewColor() {
        return cfg_barTrackColor.length > 0
            ? cfg_barTrackColor
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)
    }

    property bool syncBusy: false
    property string syncStatus: ""
    readonly property string syncHelperPath: decodeURIComponent(Qt.resolvedUrl("../code/app-memory-sync.sh").toString().replace("file://", ""))

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function syncAppearance() {
        syncRunner.run("appearance")
    }


    Kirigami.FormLayout {
        id: form
        width: page.availableWidth

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Geometry")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Background transparency:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: backgroundTransparency
            Layout.fillWidth: true
            from: 0
            to: 100
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: page.cfg_backgroundTransparency
            onMoved: page.cfg_backgroundTransparency = Math.round(value)
        }

        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
            text: Math.round(backgroundTransparency.value) + " %"
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Bar radius:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: barRadius
            Layout.fillWidth: true
            from: 0
            to: 11
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: page.cfg_barRadius
            onMoved: page.cfg_barRadius = Math.round(value)
        }

        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
            text: Math.round(barRadius.value) + " px"
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Background radius:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: backgroundRadius
            Layout.fillWidth: true
            from: 0
            to: 40
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: page.cfg_backgroundRadius
            onMoved: page.cfg_backgroundRadius = Math.round(value)
        }

        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
            text: Math.round(backgroundRadius.value) + " px"
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Content padding:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: contentPadding
            Layout.fillWidth: true
            from: 0
            to: 32
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: page.cfg_contentPadding
            onMoved: page.cfg_contentPadding = Math.round(value)
        }

        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
            text: Math.round(contentPadding.value) + " px"
        }
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Font")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Font:")
        Layout.fillWidth: true

        QQC2.Button {
            Layout.fillWidth: true
            text: page.fontSummary()
            font: page.effectiveFont
            onClicked: page.openFontDialog()
        }

        QQC2.Button {
            text: i18n("Choose…")
            onClicked: page.openFontDialog()
        }

        QQC2.ToolButton {
            icon.name: "edit-undo"
            text: i18n("System")
            display: QQC2.AbstractButton.IconOnly
            enabled: !page.usingSystemFont
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Use system font")
            onClicked: page.setSystemFont()
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Preview:")
        text: i18n("App RAM  6.4 GiB")
        font: page.effectiveFont
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Colors")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Widget background:")

        KQControls.ColorButton {
            id: backgroundColorButton
            color: page.backgroundPreviewColor()
            showAlphaChannel: false
            dialogTitle: i18n("Widget background color")
            onAccepted: function(chosenColor) {
                page.cfg_backgroundColor = String(chosenColor)
            }
        }

        QQC2.ToolButton {
            icon.name: "edit-undo"
            display: QQC2.AbstractButton.IconOnly
            enabled: page.cfg_backgroundColor.length > 0
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Use system color")
            onClicked: page.cfg_backgroundColor = ""
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Bar background:")

        KQControls.ColorButton {
            id: barTrackColorButton
            color: page.trackPreviewColor()
            showAlphaChannel: true
            dialogTitle: i18n("Bar background color")
            onAccepted: function(chosenColor) {
                page.cfg_barTrackColor = String(chosenColor)
            }
        }

        QQC2.ToolButton {
            icon.name: "edit-undo"
            display: QQC2.AbstractButton.IconOnly
            enabled: page.cfg_barTrackColor.length > 0
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Use system color")
            onClicked: page.cfg_barTrackColor = ""
        }
    }

    KQControls.ColorButton {
        Kirigami.FormData.label: i18n("Below soft limit:")
        color: page.cfg_okColor
        showAlphaChannel: false
        dialogTitle: i18n("Color below soft limit")
        onAccepted: function(chosenColor) {
            page.cfg_okColor = chosenColor
        }
    }

    KQControls.ColorButton {
        Kirigami.FormData.label: i18n("Above soft limit:")
        color: page.cfg_warningColor
        showAlphaChannel: false
        dialogTitle: i18n("Color above soft limit")
        onAccepted: function(chosenColor) {
            page.cfg_warningColor = chosenColor
        }
    }

    KQControls.ColorButton {
        Kirigami.FormData.label: i18n("Near hard limit:")
        color: page.cfg_dangerColor
        showAlphaChannel: false
        dialogTitle: i18n("Color near hard limit")
        onAccepted: function(chosenColor) {
            page.cfg_dangerColor = chosenColor
        }
    }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Instance synchronization")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Other widgets:")
            Layout.fillWidth: true

            QQC2.Button {
                Layout.fillWidth: true
                icon.name: "view-refresh"
                text: i18n("Synchronize appearance")
                enabled: !page.syncBusy
                onClicked: page.syncAppearance()
            }

        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("The appearance is copied from the currently applied appearance of this instance. If you changed anything in the configuration, click Apply first.")
            opacity: 0.76
        }

        QQC2.Label {
            visible: page.syncStatus.length > 0 || page.syncBusy
            Kirigami.FormData.label: i18n("Synchronization:")
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: page.syncBusy ? i18n("Synchronizing…") : page.syncStatus
        }
    }

    FontDialog {
        id: fontDialog
        title: i18n("Choose font")

        onAccepted: {
            page.cfg_fontFamily = selectedFont.family
            page.cfg_fontPointSize = selectedFont.pointSize
            page.cfg_fontWeight = selectedFont.weight
            page.cfg_fontItalic = selectedFont.italic
            page.cfg_fontUnderline = selectedFont.underline
            page.cfg_fontStrikeout = selectedFont.strikeout
            page.cfg_fontStyleName = selectedFont.styleName
        }
    }

    Plasma5Support.DataSource {
        id: syncRunner
        engine: "executable"
        connectedSources: []
        property string activeCommand: ""
        property string activeAction: ""

        function run(action) {
            if (page.syncBusy) return
            activeAction = action
            activeCommand = "sh " + page.shellQuote(page.syncHelperPath) + " " + page.shellQuote(action) + " " + plasmoid.id + " " + Date.now()
            page.syncBusy = true
            page.syncStatus = ""
            connectSource(activeCommand)
        }

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (sourceName !== activeCommand) return
            page.syncBusy = false
            const stdout = String(data["stdout"] || "").trim()
            const stderr = String(data["stderr"] || "").trim()
            const fields = stdout.split("\t")
            if (fields[0] === "OK" && fields[1] === "appearance") {
                page.syncStatus = i18np("Appearance was synchronized to %1 other instance.", "Appearance was synchronized to %1 other instances.", Number(fields[2]))
            } else {
                page.syncStatus = stderr.length > 0 ? stderr : (stdout.length > 0 ? stdout : i18n("Synchronization failed."))
            }
        }
    }

}
