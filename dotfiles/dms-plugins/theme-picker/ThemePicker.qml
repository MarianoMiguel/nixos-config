import QtQuick
import Quickshell
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "theme"

    signal itemsChanged

    readonly property string catalogRoot: "/run/current-system/sw/share/themeport/themes"
    readonly property var themes: [
        "catppuccin", "catppuccin-latte", "ethereal", "everforest",
        "flexoki-light", "gruvbox", "hackerman", "kanagawa", "last-horizon",
        "lumon", "lupine", "matte-black", "miasma", "nord", "osaka-jade",
        "retro-82", "ristretto", "rose-pine", "solitude", "tokyo-night",
        "vantablack", "white"
    ]

    function title(name) {
        return name.split("-").map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
    }

    function getItems(query) {
        const needle = (query || "").toLowerCase().trim();
        return themes.filter(name => needle.length === 0 || name.includes(needle) || title(name).toLowerCase().includes(needle)).map(name => ({
            name: title(name),
            icon: "material:palette",
            comment: "Themeport · coordinated desktop, shell, editor and browser colors",
            action: name,
            categories: ["Themes"],
            imageUrl: "file://" + catalogRoot + "/" + name + "/preview.png"
        }));
    }

    function executeItem(item) {
        if (!item?.action)
            return;
        if (typeof ToastService !== "undefined")
            ToastService.showInfo("Theme", "Applying " + item.name + "…");
        Quickshell.execDetached(["/run/current-system/sw/bin/themeport", "set", item.action]);
    }
}
