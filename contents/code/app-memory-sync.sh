#!/bin/sh
set -eu

ACTION=${1:-}
SOURCE_ID=${2:-}
PLUGIN_ID='cz.pitriss.appmemorybar'

case "$ACTION" in
  appearance|geometry) ;;
  *) printf 'ERROR\tunknown-action\n' >&2; exit 2 ;;
esac
case "$SOURCE_ID" in
  ''|*[!0-9]*) printf 'ERROR\tinvalid-source-id\n' >&2; exit 2 ;;
esac

if command -v qdbus6 >/dev/null 2>&1; then
  QDBUS=$(command -v qdbus6)
elif command -v qdbus >/dev/null 2>&1; then
  QDBUS=$(command -v qdbus)
elif [ -x /usr/lib/qt6/bin/qdbus ]; then
  QDBUS=/usr/lib/qt6/bin/qdbus
else
  printf 'ERROR\tqdbus-not-found\n' >&2
  exit 3
fi

if [ "$ACTION" = appearance ]; then
  SCRIPT=$(cat <<EOF_JS
(function() {
    const pluginType = "$PLUGIN_ID";
    const sourceId = $SOURCE_ID;
    const keys = [
        "backgroundTransparency", "barRadius", "backgroundRadius", "contentPadding",
        "fontFamily", "fontPointSize", "fontWeight", "fontItalic", "fontUnderline",
        "fontStrikeout", "fontStyleName", "backgroundColor", "barTrackColor",
        "okColor", "warningColor", "dangerColor"
    ];
    const defaults = {
        backgroundTransparency: 28, barRadius: 11, backgroundRadius: 11, contentPadding: 6,
        fontFamily: "", fontPointSize: 0, fontWeight: 400, fontItalic: false,
        fontUnderline: false, fontStrikeout: false, fontStyleName: "",
        backgroundColor: "", barTrackColor: "", okColor: "#35b86b",
        warningColor: "#e3a008", dangerColor: "#d83b3b"
    };
    let source = null;
    let targets = [];

    function collect(containments) {
        for (let ci = 0; ci < containments.length; ++ci) {
            const widgets = containments[ci].widgets();
            for (let wi = 0; wi < widgets.length; ++wi) {
                const widget = widgets[wi];
                if (widget.type !== pluginType) continue;
                if (widget.id === sourceId) source = widget;
                else targets.push(widget);
            }
        }
    }

    collect(desktops());
    collect(panels());
    if (!source) {
        print("ERROR\\tsource-not-found");
        return;
    }

    source.currentConfigGroup = ["General"];
    const values = {};
    for (let i = 0; i < keys.length; ++i) values[keys[i]] = source.readConfig(keys[i], defaults[keys[i]]);

    let changed = 0;
    for (let i = 0; i < targets.length; ++i) {
        const target = targets[i];
        target.currentConfigGroup = ["General"];
        for (let k = 0; k < keys.length; ++k) target.writeConfig(keys[k], values[keys[k]]);
        target.reloadConfig();
        ++changed;
    }
    print("OK\\tappearance\\t" + changed);
})();
EOF_JS
)
else
  SCRIPT=$(cat <<EOF_JS
(function() {
    const pluginType = "$PLUGIN_ID";
    const sourceId = $SOURCE_ID;
    let source = null;
    let targets = [];
    const desktopList = desktops();

    for (let ci = 0; ci < desktopList.length; ++ci) {
        const widgets = desktopList[ci].widgets();
        for (let wi = 0; wi < widgets.length; ++wi) {
            const widget = widgets[wi];
            if (widget.type !== pluginType) continue;
            if (widget.id === sourceId) source = widget;
            else targets.push(widget);
        }
    }

    if (!source) {
        print("ERROR\\tsource-not-on-desktop");
        return;
    }

    const sg = source.geometry;
    let changed = 0;
    let failed = 0;
    for (let i = 0; i < targets.length; ++i) {
        const target = targets[i];
        let tg = target.geometry;
        tg.width = sg.width;
        tg.height = sg.height;
        target.geometry = tg;
        const ag = target.geometry;
        if (Math.abs(ag.width - sg.width) <= 1 && Math.abs(ag.height - sg.height) <= 1) ++changed;
        else ++failed;
    }
    print("OK\\tgeometry\\t" + changed + "\\t" + failed + "\\t" + Math.round(sg.width) + "x" + Math.round(sg.height));
})();
EOF_JS
)
fi

OUTPUT=$($QDBUS org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$SCRIPT" 2>&1) || {
  printf 'ERROR\tqdbus-failed\t%s\n' "$OUTPUT" >&2
  exit 4
}
printf '%s\n' "$OUTPUT"
