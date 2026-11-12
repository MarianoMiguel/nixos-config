import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    layerNamespacePlugin: "folio-sidebar-button"

    pillClickAction: (x, y, width, section, screen) => {
        if (root.pluginService)
            root.pluginService.setGlobalVar(root.pluginId, "request", {
                screenName: screen?.name || "", serial: Date.now()
            });
    }

    horizontalBarPill: Component {
        Row {
            spacing: 5
            DankIcon {
                name: "dock_to_right"
                size: Theme.iconSize
                color: Theme.surfaceText
            }
            Rectangle {
                width: 5; height: 5; radius: 2.5
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.primary
                visible: NotificationService.unreadCount > 0
            }
        }
    }
    verticalBarPill: horizontalBarPill
}
