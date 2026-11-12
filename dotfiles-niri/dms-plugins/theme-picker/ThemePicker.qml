import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

QtObject {
    id: root
    property var pluginService: null
    property string trigger: "theme"
    signal itemsChanged
    readonly property string dataRoot: "/run/current-system/sw/share/azure-folio"
    property var selection: ({collection:"dore",mode:"light",ink:"azure"})
    readonly property var collections: [
        {id:"dore",name:"Doré",art:"dore-nightfall",description:"Paradise Lost · engraved plates"},
        {id:"summer",name:"European Summer",art:"summer-riviera",description:"Riviera, Sicily and yachts"},
        {id:"argentina",name:"Argentina",art:"argentina-buenos-aires",description:"Buenos Aires, mate, tango and Patagonia"},
        {id:"ronin",name:"Ronin",art:"ronin-crossing",description:"Wandering samurai, mountain mist and Japanese shrine paths"}
    ]
    property FileView stateFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/nixos-config/azure-folio/selection.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.selection = JSON.parse(text()); root.itemsChanged(); } catch (e) {} }
    }
    function getItems(query) {
        const needle = (query || "").trim().toLowerCase();
        let items = collections.map(c => ({
            name: (selection.collection === c.id ? "✓ " : "") + c.name,
            icon:"material:landscape", comment:c.description,
            action:"collection:" + c.id, categories:["Art collections"],
            imageUrl:"file://" + dataRoot + "/art/" + c.art + "/" + (selection.ink || "azure") + "-" + (selection.mode || "light") + "-desktop.png"
        }));
        [{id:"light",name:"Daylight",icon:"light_mode"},{id:"dark",name:"After hours",icon:"dark_mode"}].forEach(m => items.push({
            name:(selection.mode === m.id ? "✓ " : "") + m.name, icon:"material:"+m.icon,
            comment:"Light and dark · same art and ink",action:"mode:"+m.id,categories:["Light & dark"]
        }));
        ["azure","cobalt","slate"].forEach(ink => items.push({
            name:(selection.ink === ink ? "✓ " : "") + ink.charAt(0).toUpperCase()+ink.slice(1), icon:"material:palette",
            comment:"Blue ink · same collection and mode",action:"ink:"+ink,categories:["Blue ink"]
        }));
        return items.filter(i => !needle || (i.name + " " + i.comment + " " + i.categories.join(" ")).toLowerCase().includes(needle));
    }
    function executeItem(item) {
        if (!item?.action) return;
        const parts = item.action.split(":");
        const allowed = {collection:collections.map(c => c.id),mode:["light","dark"],ink:["azure","cobalt","slate"]};
        if (!allowed[parts[0]]?.includes(parts[1])) return;
        Quickshell.execDetached(["/run/current-system/sw/bin/azure-folio","set","--"+parts[0],parts[1]]);
        ToastService.showInfo("Azure Folio", "Applying " + item.name.replace("✓ ", "") + "…");
    }
}
