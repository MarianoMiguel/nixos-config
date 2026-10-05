import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

QtObject {
    id: root
    property var pluginService: null
    property string trigger: "wall"
    signal itemsChanged
    property var appearance: ({images:[]})
    property FileView stateFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/nixos-config/azure-folio/appearance.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.appearance=JSON.parse(text());root.itemsChanged(); } catch (e) {} }
    }
    function getItems(query) {
        const needle=(query||"").toLowerCase().trim();
        return (appearance.images||[]).map((art,index)=>({
            name:(index===appearance.art?"✓ ":"")+art.title,
            icon:"material:wallpaper",comment:appearance.collectionName+" · "+art.credit,
            action:String(index),categories:["Azure Folio wallpapers"],imageUrl:"file://"+art.desktop
        })).filter(i=>!needle||(i.name+" "+i.comment).toLowerCase().includes(needle));
    }
    function executeItem(item) {
        const index=Number(item?.action);
        if(!Number.isInteger(index)||index<0||index>=(appearance.images||[]).length)return;
        Quickshell.execDetached(["/run/current-system/sw/bin/azure-folio","set","--art",String(index)]);
        ToastService.showInfo("Azure Folio",item.name.replace("✓ ",""));
    }
}
