#!/bin/sh
set -eu

OLD_ID='cz.chytrex.bravememorybar'
NEW_ID='cz.pitriss.appmemorybar'
NEW_CTL="$HOME/.local/share/plasma/plasmoids/$NEW_ID/contents/code/app-memoryctl.py"

if command -v qdbus6 >/dev/null 2>&1; then
    QDBUS=$(command -v qdbus6)
elif command -v qdbus >/dev/null 2>&1; then
    QDBUS=$(command -v qdbus)
elif [ -x /usr/lib/qt6/bin/qdbus ]; then
    QDBUS=/usr/lib/qt6/bin/qdbus
else
    printf '%s\n' 'ERROR: qdbus6/qdbus nebyl nalezen.' >&2
    exit 2
fi

[ -f "$NEW_CTL" ] || {
    printf 'ERROR: nový plasmoid %s není nainstalovaný.\n' "$NEW_ID" >&2
    exit 3
}

SCRIPT=$(cat <<'EOF_JS'
(function() {
    const oldType = "cz.chytrex.bravememorybar";
    const newType = "cz.pitriss.appmemorybar";
    const keys = [
        "targetScopePrefix", "targetDisplayName", "targetExecutable",
        "maintainLimitsByExecutable", "desiredHighBytes", "desiredMaxBytes",
        "backgroundTransparency", "barRadius", "backgroundRadius", "contentPadding",
        "fontFamily", "fontPointSize", "fontWeight", "fontItalic", "fontUnderline",
        "fontStrikeout", "fontStyleName", "backgroundColor", "barTrackColor",
        "okColor", "warningColor", "dangerColor"
    ];

    if (!knownWidgetTypes.includes(newType)) {
        print("ERROR\tnew-widget-not-installed");
        return;
    }

    let migrated = 0;
    let failed = 0;

    function migrateContainment(containment) {
        const widgets = containment.widgets();
        for (let i = 0; i < widgets.length; ++i) {
            const oldWidget = widgets[i];
            if (oldWidget.type !== oldType) continue;

            const oldGeometry = oldWidget.geometry;
            const oldIndex = oldWidget.index;
            const oldShortcut = oldWidget.globalShortcut;
            oldWidget.currentConfigGroup = ["General"];

            const values = {};
            for (let k = 0; k < keys.length; ++k) {
                values[keys[k]] = oldWidget.readConfig(keys[k], "");
            }

            let newWidget = null;
            try {
                newWidget = containment.addWidget(newType);
            } catch (e) {
                print("ERROR\tadd-widget\t" + oldWidget.id + "\t" + e);
                ++failed;
                continue;
            }
            if (!newWidget) {
                print("ERROR\tadd-widget-null\t" + oldWidget.id);
                ++failed;
                continue;
            }

            newWidget.currentConfigGroup = ["General"];
            for (let k = 0; k < keys.length; ++k) {
                newWidget.writeConfig(keys[k], values[keys[k]]);
            }
            try { newWidget.geometry = oldGeometry; } catch (e) {}
            try { newWidget.index = oldIndex; } catch (e) {}
            try { newWidget.globalShortcut = oldShortcut; } catch (e) {}
            newWidget.reloadConfig();

            oldWidget.remove();
            ++migrated;
        }
    }

    const ds = desktops();
    for (let i = 0; i < ds.length; ++i) migrateContainment(ds[i]);
    const ps = panels();
    for (let i = 0; i < ps.length; ++i) migrateContainment(ps[i]);

    print("OK\tmigrated\t" + migrated + "\tfailed\t" + failed);
})();
EOF_JS
)

OUTPUT=$($QDBUS org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$SCRIPT" 2>&1) || {
    printf 'ERROR: Plasma migration script selhal: %s\n' "$OUTPUT" >&2
    exit 4
}
printf '%s\n' "$OUTPUT"

case "$OUTPUT" in
    *ERROR*) exit 5 ;;
esac

# Přepiš app-memory-bar.service tak, aby ExecStart ukazoval do nového plugin ID,
# a načti backend 0.10.0. Konfigurace aplikací zůstává v ~/.config/app-memory-bar/.
python3 "$NEW_CTL" ensure

printf '\nMigrace instancí je hotová. Starý balíček lze nyní odstranit:\n'
printf '  kpackagetool6 -t Plasma/Applet -r %s\n' "$OLD_ID"
