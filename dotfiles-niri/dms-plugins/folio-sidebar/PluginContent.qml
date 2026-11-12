import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root
    required property string sourcePlugin
    required property var sidebar
    property bool expanded: false
    property var controller: null
    property string errorMessage: ""
    property bool keepHeader: false
    // PopoutComponent's small host contract is the only adaptation needed.
    property bool shouldBeVisible: sidebar.shouldBeVisible && expanded
    property var screen: sidebar.screen
    implicitHeight: body.item ? body.item.implicitHeight : fallback.implicitHeight + 24

    function close() { sidebar.expandedSection = ""; }
    function release() {
        body.sourceComponent = null;
        if (controller) controller.destroy();
        controller = null;
    }
    function load() {
        release();
        sidebar.reportPanel(sourcePlugin, false);
        const component = PluginService.getWidgetComponents()[sourcePlugin];
        if (!component) {
            errorMessage = "Enable " + sourcePlugin + " in DMS Plugins to use this section.";
            return;
        }
        controller = component.createObject(controllerHost, {
            pluginId: sourcePlugin, pluginService: PluginService, visible: false
        });
        if (!controller || !controller.popoutContent) {
            errorMessage = "This plugin no longer provides a panel. Its standalone control is still available in DMS.";
            return;
        }
        errorMessage = "";
        body.sourceComponent = controller.popoutContent;
        syncScreen();
    }
    function syncScreen() {
        if (controller && "outputName" in controller)
            controller.outputName = screen?.name || "";
    }
    onScreenChanged: syncScreen()
    Component.onCompleted: load()
    Component.onDestruction: release()
    Connections {
        target: PluginService
        function onPluginLoaded(id) { if (id === root.sourcePlugin) root.load(); }
        function onPluginUnloaded(id) {
            if (id === root.sourcePlugin) {
                root.release();
                root.errorMessage = "This plugin is disabled in DMS.";
            }
        }
    }
    Item { id: controllerHost; visible: false }
    Loader {
        id: body
        width: parent.width
        onLoaded: {
            root.sidebar.reportPanel(root.sourcePlugin, true);
            if ("parentPopout" in item) item.parentPopout = root;
            if ("closePopout" in item) item.closePopout = () => root.close();
            if ("showCloseButton" in item) item.showCloseButton = false;
            if (!root.keepHeader && "headerText" in item) item.headerText = "";
        }
    }
    StyledText {
        id: fallback
        anchors.left: parent.left; anchors.right: parent.right
        anchors.margins: 12; y: 12
        visible: !body.item
        text: root.errorMessage
        wrapMode: Text.WordWrap
        font.pixelSize: 12; color: Theme.surfaceVariantText
    }
}
