import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "wall"

    signal itemsChanged

    readonly property string wallpaperRoot: "/home/mariano/Pictures/Wallpapers"

    function title(filename) {
        let stem = filename.replace(/\.(jpe?g|png|webp)$/i, "");
        return stem.replace("--", " · ").replace(/[-_]+/g, " ").split(" ").filter(Boolean).map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
    }

    function getItems(query) {
        const needle = (query || "").toLowerCase().trim();
        const results = [];
        for (let index = 0; index < wallpaperModel.count; index++) {
            const filename = wallpaperModel.get(index, "fileName") || "";
            const path = wallpaperModel.get(index, "filePath") || "";
            const label = title(filename);
            if (needle.length !== 0 && !filename.toLowerCase().includes(needle) && !label.toLowerCase().includes(needle))
                continue;
            results.push({
                name: label,
                icon: "material:wallpaper",
                comment: filename.includes("--") ? "Omarchy Quattro wallpaper" : "Personal wallpaper",
                action: path,
                categories: ["Wallpapers"],
                imageUrl: "file://" + encodeURI(path)
            });
        }
        return results;
    }

    function executeItem(item) {
        if (!item?.action)
            return;
        Quickshell.execDetached(["/run/current-system/sw/bin/dms", "ipc", "call", "wallpaper", "set", item.action]);
        if (typeof ToastService !== "undefined")
            ToastService.showInfo("Wallpaper", item.name);
    }

    property FolderListModel wallpaperModel: FolderListModel {
        folder: "file:///home/mariano/Pictures/Wallpapers"
        showDirs: false
        showDotAndDotDot: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP"]
        sortField: FolderListModel.Name
        sortReversed: false

        onCountChanged: root.itemsChanged()
        onStatusChanged: root.itemsChanged()
    }
}
