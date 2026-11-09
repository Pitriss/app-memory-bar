import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

QQC2.ScrollView {
    id: page
    clip: true
    contentWidth: availableWidth
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
    QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded

    property string cfg_targetScopePrefix: "app-org.chromium.Chromium"
    property string cfg_targetDisplayName: "Brave"
    property string cfg_targetExecutable: ""
    property bool cfg_maintainLimitsByExecutable: false
    property string cfg_desiredHighBytes: "0"
    property string cfg_desiredMaxBytes: "0"

    property bool loadingLimitEditors: false
    property bool scanning: false
    property bool changingLimits: false
    property string scanStatus: ""
    property string actionStatus: ""

    readonly property double gib: 1073741824
    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/app-memory-probe.sh").toString().replace("file://", ""))
    readonly property string scanCommandBase: "sh " + shellQuote(helperPath) + " scan"
    property string activeScanCommand: ""

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function formatGiB(value) {
        if (String(value) === "max") return i18n("bez limitu")
        const bytes = Number(value)
        if (!isFinite(bytes) || bytes < 0) return "?"
        return (bytes / gib).toFixed(1) + " GiB"
    }

    function finiteLimit(value) {
        return String(value) !== "max" && isFinite(Number(value)) && Number(value) > 0
    }

    function selectedItem() {
        if (applicationCombo.currentIndex < 0 || applicationCombo.currentIndex >= appModel.count) return null
        return appModel.get(applicationCombo.currentIndex)
    }

    function findSelection() {
        for (let i = 0; i < appModel.count; ++i) {
            const item = appModel.get(i)
            if (cfg_targetExecutable.length > 0 && item.exe === cfg_targetExecutable) return i
        }
        const wanted = String(cfg_targetDisplayName || "").toLowerCase()
        let found = -1
        let count = 0
        for (let i = 0; i < appModel.count; ++i) {
            const item = appModel.get(i)
            if (wanted.length > 0 && String(item.name).toLowerCase() === wanted) {
                found = i
                ++count
            }
        }
        return count === 1 ? found : -1
    }

    function defaultHighGiBTenths(currentBytes) {
        const currentGiB = Math.max(0, Number(currentBytes) / gib)
        return Math.max(10, Math.ceil(currentGiB * 15))
    }

    function defaultMaxGiBTenths(currentBytes, highTenths) {
        const currentGiB = Math.max(0, Number(currentBytes) / gib)
        return Math.max(highTenths + 10, 20, Math.ceil(currentGiB * 20))
    }

    function loadLimitEditors() {
        const item = selectedItem()
        if (!item) return
        loadingLimitEditors = true
        const storedHigh = Number(cfg_desiredHighBytes)
        const storedMax = Number(cfg_desiredMaxBytes)
        const storedForSelection = cfg_targetExecutable.length > 0 && item.exe === cfg_targetExecutable
            && isFinite(storedHigh) && isFinite(storedMax) && storedHigh > 0 && storedMax > storedHigh
        let highTenths
        let maxTenths
        if (storedForSelection) {
            highTenths = Math.max(1, Math.round(storedHigh / gib * 10))
            maxTenths = Math.max(highTenths + 1, Math.round(storedMax / gib * 10))
        } else {
            highTenths = finiteLimit(item.high) ? Math.max(1, Math.round(Number(item.high) / gib * 10)) : defaultHighGiBTenths(item.current)
            maxTenths = finiteLimit(item.max) ? Math.max(highTenths + 1, Math.round(Number(item.max) / gib * 10)) : defaultMaxGiBTenths(item.current, highTenths)
        }
        highSpin.value = highTenths
        maxSpin.value = maxTenths
        loadingLimitEditors = false
    }

    function ensureCurrentSelection() {
        let index = findSelection()
        if (index < 0 && cfg_targetExecutable.length > 0) {
            const name = cfg_targetDisplayName.length > 0 ? cfg_targetDisplayName : cfg_targetExecutable.split("/").pop()
            appModel.append({
                name: name,
                exe: cfg_targetExecutable,
                current: "0",
                high: "max",
                max: "max",
                running: false,
                unitCount: 0,
                units: "",
                processes: "",
                text: i18n("%1 — aktuálně neběží", name)
            })
            index = appModel.count - 1
        }
        if (index >= 0) {
            applicationCombo.currentIndex = index
            const item = appModel.get(index)
            if (cfg_targetExecutable.length === 0 && item.running && item.exe.length > 0) {
                cfg_targetExecutable = item.exe
                cfg_targetDisplayName = item.name
                actionStatus = i18n("Vazba aplikace byla doplněna na %1.", item.exe)
            }
            loadLimitEditors()
        }
    }

    function parseScan(output) {
        appModel.clear()
        const lines = String(output || "").trim().split("\n")
        for (let i = 0; i < lines.length; ++i) {
            if (lines[i].trim().length === 0) continue
            const fields = lines[i].split("\t")
            if (fields.length < 8) continue
            const name = fields[0]
            const exe = fields[1]
            const current = fields[2]
            const high = fields[3]
            const max = fields[4]
            const unitCount = Number(fields[5]) || 0
            const units = fields[6]
            const processes = fields.slice(7).join("\t")
            const limitText = finiteLimit(high) && finiteLimit(max)
                ? "HIGH " + formatGiB(high) + " / MAX " + formatGiB(max)
                : i18n("bez společného limitu")
            const running = unitCount > 0
            appModel.append({
                name: name,
                exe: exe,
                current: current,
                high: high,
                max: max,
                running: running,
                unitCount: unitCount,
                units: units,
                processes: processes,
                text: running
                    ? name + " (" + exe.split("/").pop() + ")  —  " + formatGiB(current)
                        + " · " + limitText + " · " + i18np("%1 jednotka", "%1 jednotky", unitCount)
                    : i18n("%1 (%2) — aktuálně neběží", name, exe.split("/").pop())
            })
        }
        scanning = false
        scanStatus = appModel.count === 0
            ? i18n("Nebyla nalezena žádná aplikace v uživatelském app.slice.")
            : i18np("Nalezena %1 aplikace.", "Nalezeny %1 aplikace.", appModel.count)
        ensureCurrentSelection()
    }

    function selectApplication(index) {
        if (index < 0 || index >= appModel.count) return
        const item = appModel.get(index)
        cfg_targetExecutable = item.exe
        cfg_targetDisplayName = item.name
        cfg_targetScopePrefix = ""
        cfg_desiredHighBytes = "0"
        cfg_desiredMaxBytes = "0"
        cfg_maintainLimitsByExecutable = false
        actionStatus = ""
        loadLimitEditors()
        cfg_desiredHighBytes = String(requestedHighBytes())
        cfg_desiredMaxBytes = String(requestedMaxBytes())
    }

    function requestedHighBytes() { return Math.round(highSpin.value / 10.0 * gib) }
    function requestedMaxBytes() { return Math.round(maxSpin.value / 10.0 * gib) }

    function limitsValidForApply() {
        return requestedHighBytes() > 0 && requestedMaxBytes() > requestedHighBytes() && selectedItem() !== null
    }

    function applyRuntime() {
        const item = selectedItem()
        if (!item || !item.running || item.exe.length === 0 || !limitsValidForApply()) return
        manager.run("sh " + shellQuote(helperPath) + " apply-app " + shellQuote(item.exe)
                    + " " + requestedHighBytes() + " " + requestedMaxBytes())
    }

    function clearRuntime() {
        const item = selectedItem()
        if (!item || !item.running || item.exe.length === 0) return
        manager.run("sh " + shellQuote(helperPath) + " clear-app " + shellQuote(item.exe))
    }

    ListModel { id: appModel }

    Kirigami.FormLayout {
        id: form
        width: page.availableWidth

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Aplikace v tomto přihlášení")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Aplikace:")
        Layout.fillWidth: true
        QQC2.ComboBox {
            id: applicationCombo
            Layout.fillWidth: true
            model: appModel
            textRole: "text"
            enabled: appModel.count > 0 && !page.scanning && !page.changingLimits
            onActivated: function(index) { page.selectApplication(index) }
        }
        QQC2.Button {
            icon.name: "view-refresh"
            text: page.scanning ? i18n("Skenovat znovu") : i18n("Skenovat")
            enabled: !page.changingLimits
            onClicked: scanner.refresh()
        }
        QQC2.BusyIndicator {
            visible: page.scanning
            running: page.scanning
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: implicitWidth
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Executable:")
        Layout.fillWidth: true
        wrapMode: Text.WrapAnywhere
        text: { const item = page.selectedItem(); return item && item.exe.length > 0 ? item.exe : "—" }
        font.family: "monospace"
        opacity: 0.82
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Systemd jednotky:")
        Layout.fillWidth: true
        wrapMode: Text.WrapAnywhere
        text: {
            const item = page.selectedItem()
            if (!item || !item.running) return i18n("Aplikace právě neběží.")
            return i18np("%1 jednotka: %2", "%1 jednotky: %2", item.unitCount, item.units)
        }
        font.family: "monospace"
        opacity: 0.82
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Procesy:")
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: {
            const item = page.selectedItem()
            if (!item || !item.running) return "—"
            return item.processes.length > 0 ? item.processes : i18n("Procesy se nepodařilo určit.")
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("Backend běží jako systemd --user služba. Widget čte cache podle přesné executable; globální sken se používá jen pro výběr nové aplikace. Krátký výpadek detekce proto nezpůsobí okamžité zmizení aplikace.")
        opacity: 0.76
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Celkový paměťový budget aplikace")
    }

    QQC2.SpinBox {
        id: highSpin
        Kirigami.FormData.label: i18n("Soft limit (MemoryHigh):")
        from: 1
        to: 10240
        stepSize: 1
        editable: true
        enabled: page.selectedItem() !== null && !page.changingLimits
        textFromValue: function(value, locale) { return (value / 10.0).toFixed(1) + " GiB" }
        valueFromText: function(text, locale) {
            const value = parseFloat(String(text).replace(",", "."))
            return isFinite(value) ? Math.round(value * 10) : highSpin.value
        }
        onValueModified: if (!page.loadingLimitEditors) page.cfg_desiredHighBytes = String(page.requestedHighBytes())
    }

    QQC2.SpinBox {
        id: maxSpin
        Kirigami.FormData.label: i18n("Hard limit (MemoryMax):")
        from: 2
        to: 10240
        stepSize: 1
        editable: true
        enabled: page.selectedItem() !== null && !page.changingLimits
        textFromValue: function(value, locale) { return (value / 10.0).toFixed(1) + " GiB" }
        valueFromText: function(text, locale) {
            const value = parseFloat(String(text).replace(",", "."))
            return isFinite(value) ? Math.round(value * 10) : maxSpin.value
        }
        onValueModified: if (!page.loadingLimitEditors) page.cfg_desiredMaxBytes = String(page.requestedMaxBytes())
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Kontrola:")
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: {
            const item = page.selectedItem()
            if (!item) return Kirigami.Theme.disabledTextColor
            if (page.requestedMaxBytes() <= page.requestedHighBytes()) return Kirigami.Theme.negativeTextColor
            if (item.running && Number(item.current) >= page.requestedMaxBytes()) return Kirigami.Theme.neutralTextColor
            return Kirigami.Theme.positiveTextColor
        }
        text: {
            const item = page.selectedItem()
            if (!item) return i18n("Vyber aplikaci.")
            if (page.requestedMaxBytes() <= page.requestedHighBytes()) return i18n("Hard limit musí být vyšší než soft limit.")
            if (item.running && Number(item.current) >= page.requestedMaxBytes()) return i18n("Aplikace je nyní nad hard limitem (%1). Widget aplikuje MemoryHigh a MemoryMax odloží, dokud spotřeba neklesne.", page.formatGiB(item.current))
            return i18n("Budget lze bezpečně aplikovat na všechny nalezené jednotky aplikace.")
        }
    }

    QQC2.CheckBox {
        Kirigami.FormData.label: i18n("Persistence:")
        text: i18n("Udržovat celkový limit automaticky")
        checked: page.cfg_maintainLimitsByExecutable
        enabled: page.selectedItem() !== null && page.limitsValidForApply() && !page.changingLimits
        onToggled: {
            page.cfg_maintainLimitsByExecutable = checked
            if (checked) {
                page.cfg_desiredHighBytes = String(page.requestedHighBytes())
                page.cfg_desiredMaxBytes = String(page.requestedMaxBytes())
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("Persistence je nyní udržována samostatnou systemd --user službou, takže přežije restart plasmashellu. Soft limit se rozdělí mezi všechny aktuální systemd jednotky aplikace. U jediné jednotky se aplikuje i MemoryMax; u více sourozeneckých jednotek zůstává hard limit bezpečně jen celkovým targetem.")
        opacity: 0.76
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Akce:")
        Layout.fillWidth: true
        QQC2.Button {
            Layout.fillWidth: true
            icon.name: "media-playback-start"
            text: i18n("Aplikovat na celou aplikaci")
            enabled: {
                const item = page.selectedItem()
                return item && item.running && item.exe.length > 0 && !page.scanning && !page.changingLimits && page.limitsValidForApply()
            }
            onClicked: page.applyRuntime()
        }
        QQC2.Button {
            Layout.fillWidth: true
            icon.name: "edit-clear"
            text: i18n("Uvolnit runtime limity")
            enabled: {
                const item = page.selectedItem()
                return item && item.running && item.exe.length > 0 && !page.scanning && !page.changingLimits
            }
            onClicked: clearDialog.open()
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Stav:")
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: page.changingLimits ? i18n("Provádím změnu…") : (page.actionStatus.length > 0 ? page.actionStatus : page.scanStatus)
        opacity: 0.82
    }

    }

    QQC2.Dialog {
        id: clearDialog
        modal: true
        title: i18n("Uvolnit runtime limity?")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        contentItem: QQC2.Label {
            width: Math.min(Kirigami.Units.gridUnit * 30, implicitWidth)
            wrapMode: Text.WordWrap
            text: i18n("Nastaví MemoryHigh a MemoryMax na infinity u všech právě nalezených jednotek této aplikace. Automatickou persistenci vypni zvlášť, jinak widget limity při dalším pollu znovu nastaví.")
        }
        onAccepted: page.clearRuntime()
    }

    Timer {
        id: scanWatchdog
        interval: 10000
        repeat: false
        onTriggered: {
            if (!page.scanning) return
            if (page.activeScanCommand.length > 0 && scanner.connectedSources.indexOf(page.activeScanCommand) !== -1)
                scanner.disconnectSource(page.activeScanCommand)
            page.scanning = false
            page.scanStatus = i18n("Sken nevrátil výsledek. Tlačítkem Skenovat jej můžeš okamžitě spustit znovu.")
        }
    }

    Plasma5Support.DataSource {
        id: scanner
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (sourceName !== page.activeScanCommand) return
            scanWatchdog.stop()
            const stdout = String(data["stdout"] || "")
            const stderr = String(data["stderr"] || "").trim()
            page.parseScan(stdout)
            if (appModel.count === 0 && stderr.length > 0)
                page.scanStatus = i18n("Sken selhal: %1", stderr)
        }
        function refresh() {
            if (page.activeScanCommand.length > 0 && connectedSources.indexOf(page.activeScanCommand) !== -1)
                disconnectSource(page.activeScanCommand)
            page.activeScanCommand = page.scanCommandBase + " " + Date.now()
            page.scanning = true
            page.scanStatus = ""
            scanWatchdog.restart()
            connectSource(page.activeScanCommand)
        }
    }

    Plasma5Support.DataSource {
        id: manager
        engine: "executable"
        connectedSources: []
        property string activeCommand: ""
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (sourceName !== activeCommand) return
            const stdout = String(data["stdout"] || "").trim()
            const stderr = String(data["stderr"] || "").trim()
            page.changingLimits = false
            if (stdout.indexOf("OK\t") === 0) {
                page.actionStatus = stdout.indexOf("OK\tcleared") === 0
                    ? i18n("Runtime limity aplikace byly uvolněny.")
                    : (stdout.indexOf("pending-max") >= 0
                        ? i18n("Soft limit byl aplikován; hard limit čeká na pokles spotřeby.")
                        : (stdout.indexOf("soft-only-multi") >= 0
                            ? i18n("Soft budget byl aplikován na všechny jednotky; hard limit je pouze celkový vizuální target, protože aplikace používá více sourozeneckých cgroups.")
                            : i18n("Paměťový budget byl aplikován na aplikaci.")))
            } else {
                page.actionStatus = stderr.length > 0 ? stderr : (stdout.length > 0 ? stdout : i18n("Změna limitů selhala."))
            }
            scanner.refresh()
        }
        function run(command) {
            if (page.changingLimits) return
            activeCommand = command
            page.changingLimits = true
            page.actionStatus = ""
            connectSource(command)
        }
    }

    Component.onCompleted: scanner.refresh()
}
