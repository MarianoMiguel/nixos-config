import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.ControlCenter.Details

Item {
    id: root
    property string pluginId: "folioSidebar"
    property var pluginService: null
    property var screen: null
    property bool shouldBeVisible: false
    property string expandedSection: "world"
    readonly property var sections: ["sound", "world", "layout", "focus", "notifications", "battery", "codex"]
    property var panelHealth: ({})
    function reportPanel(name, healthy) {
        const next = Object.assign({}, panelHealth);
        next[name] = healthy;
        panelHealth = next;
    }
    property real progress: shouldBeVisible ? 1 : 0
    Behavior on progress { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    function resolveScreen(name) {
        for (const candidate of Quickshell.screens)
            if (candidate.name === name) return candidate;
        return CompositorService.getFocusedScreen();
    }
    function openOn(target) {
        if (SessionService.locked || !target) return;
        if (screen !== target && shouldBeVisible) PopoutManager.hidePopout(root);
        screen = target;
        shouldBeVisible = true;
        PopoutManager.showPopout(root);
        Qt.callLater(() => page.forceActiveFocus());
    }
    function toggleOn(target) {
        if (shouldBeVisible && screen === target) close();
        else openOn(target);
    }
    function close() {
        shouldBeVisible = false;
        PopoutManager.hidePopout(root);
    }
    function selectSection(name) {
        expandedSection = expandedSection === name ? "" : name;
        if (expandedSection) revealTimer.restart();
    }
    function revealSection() {
        for (const child of column.children) {
            if (child.objectName !== expandedSection) continue;
            const bottom = child.y + Math.min(child.height, scroll.height - 16);
            if (bottom > scroll.contentY + scroll.height || child.y < scroll.contentY)
                scroll.contentY = Math.max(0, Math.min(child.y - 8, scroll.contentHeight - scroll.height));
            return;
        }
    }
    function launchControlCenter() {
        close();
        Quickshell.execDetached(["dms", "ipc", "call", "control-center", "open"]);
    }
    function launchPowerMenu() {
        close();
        // Let DMS finish loading its menu and release the drawer's focus first.
        PopoutService.powerMenuModalLoader.active = true;
        powerMenuTimer.restart();
    }
    Component.onDestruction: PopoutManager.hidePopout(root)
    Connections {
        target: root.pluginService
        function onGlobalVarChanged(id, key) {
            if (id !== root.pluginId || key !== "request") return;
            const request = root.pluginService.getGlobalVar(id, key, {});
            root.toggleOn(root.resolveScreen(request.screenName || ""));
        }
    }
    Connections {
        target: SessionService
        function onLockedChanged() { if (SessionService.locked) root.close(); }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.screen && !Quickshell.screens.includes(root.screen)) root.close();
        }
    }
    IpcHandler {
        target: "folioSidebar"
        function toggle(): string {
            root.toggleOn(root.resolveScreen(""));
            return root.shouldBeVisible ? "open" : "closed";
        }
        function open(): string { root.openOn(root.resolveScreen("")); return "open"; }
        function close(): string { root.close(); return "closed"; }
        function section(name: string): string {
            if (!root.sections.includes(name)) return "ERROR: unknown section";
            root.expandedSection = name;
            root.openOn(root.resolveScreen(""));
            revealTimer.restart();
            return name;
        }
        function status(): string {
            return JSON.stringify({open: root.shouldBeVisible, screen: root.screen?.name || "", section: root.expandedSection, panels: root.panelHealth});
        }
    }

    Timer { id: powerMenuTimer; interval: 100; onTriggered: PopoutService.openPowerMenu() }
    Timer { id: revealTimer; interval: 32; onTriggered: root.revealSection() }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    PanelWindow {
        id: window
        screen: root.screen
        visible: root.shouldBeVisible || root.progress > 0
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "dms:folio-sidebar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: root.shouldBeVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.isLightMode ? "#514536" : "#000000", Theme.isLightMode ? 0.08 : 0.22)
            opacity: root.progress
        }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
        Rectangle {
            id: panel
            width: Math.min(448, window.width - 24)
            height: window.height - 24
            x: window.width - width - 12 + (1 - root.progress) * (width + 12)
            y: 12
            radius: Theme.cornerRadius
            color: Theme.surface
            border.color: Theme.outlineVariant
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.isLightMode ? "#372f24" : "#000000"
                shadowOpacity: 0.22
                shadowBlur: 0.8
                shadowHorizontalOffset: -4
                shadowVerticalOffset: 2
            }
            // Consume clicks on blank panel areas; only clicks outside dismiss.
            MouseArea { anchors.fill: parent }
            FocusScope {
                id: page
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: event => { root.close(); event.accepted = true; }

                Item {
                    id: masthead
                    x: 24; y: 18; width: parent.width - 48; height: 30
                    StyledText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "b."
                        font.family: "Jacquard 24"; font.pixelSize: 32
                        color: Theme.primary
                    }
                    StyledText {
                        anchors.left: parent.left; anchors.leftMargin: 38
                        anchors.verticalCenter: parent.verticalCenter
                        text: "THE DAILY FOLIO"
                        font.family: SettingsData.monoFontFamily
                        font.pixelSize: 10; font.letterSpacing: 1.5
                        color: Theme.surfaceVariantText
                    }
                    DankActionButton {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        iconName: "close"; buttonSize: 28
                        Accessible.name: "Close sidebar"
                        onClicked: root.close()
                    }
                }
                DankFlickable {
                    id: scroll
                    anchors.top: masthead.bottom; anchors.topMargin: 14
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: footer.top; anchors.bottomMargin: 12
                    anchors.leftMargin: 24; anchors.rightMargin: 24
                    clip: true
                    contentWidth: width
                    contentHeight: column.implicitHeight
                    Column {
                        id: column
                        width: scroll.width
                        spacing: 12
                        Column {
                            width: parent.width
                            spacing: 3
                            Text {
                                text: Qt.formatDateTime(clock.date, "hh:mm")
                                color: Theme.primary
                                font.family: "Jacquard 24"; font.pixelSize: 116
                                font.letterSpacing: -4
                                height: 119
                            }
                            StyledText {
                                text: Qt.formatDateTime(clock.date, "dddd, d MMMM").toUpperCase()
                                font.family: SettingsData.monoFontFamily
                                font.pixelSize: 11; font.letterSpacing: 1
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: "A moment to take it all in."
                                font.pixelSize: 12; color: Theme.surfaceVariantText
                                topPadding: 5; bottomPadding: 12
                            }
                        }
                        MediaCard { width: parent.width }
                        SidebarSection {
                            width: parent.width; title: "Sound"; icon: AudioService.sinkVolumeIconName
                            summary: AudioService.sink ? AudioService.displayName(AudioService.sink) + (AudioService.sink.audio?.muted ? " · muted" : " · " + Math.round((AudioService.sink.audio?.volume || 0) * 100) + "%") : "Connect an output device"
                            objectName: "sound"
                            expanded: root.expandedSection === "sound"
                            onToggled: root.selectSection("sound")
                            body: Component { AudioPanel { sidebar: root } }
                        }
                        SidebarSection {
                            width: parent.width; title: "World clock"; icon: "public"
                            summary: "Campana · New York · Los Angeles · Sydney"
                            objectName: "world"
                            expanded: root.expandedSection === "world"
                            onToggled: root.selectSection("world")
                            body: Component {
                                PluginContent {
                                    sourcePlugin: "worldClock"; sidebar: root
                                    expanded: root.expandedSection === "world"
                                }
                            }
                        }
                        SidebarSection {
                            width: parent.width; title: "Layout"; icon: "space_dashboard"
                            summary: "Tile, float or focus · " + (root.screen?.name || "this display")
                            objectName: "layout"
                            expanded: root.expandedSection === "layout"
                            onToggled: root.selectSection("layout")
                            body: Component {
                                PluginContent {
                                    sourcePlugin: "workspaceModes"; sidebar: root
                                    expanded: root.expandedSection === "layout"
                                }
                            }
                        }
                        SidebarSection {
                            width: parent.width; title: "Focus"; icon: "center_focus_strong"
                            summary: SessionData.doNotDisturb ? "Notifications silenced" : "Quiet controls & personal reminders"
                            objectName: "focus"
                            expanded: root.expandedSection === "focus"
                            onToggled: root.selectSection("focus")
                            body: Component {
                                PluginContent {
                                    sourcePlugin: "focus"; sidebar: root
                                    expanded: root.expandedSection === "focus"
                                }
                            }
                        }
                        SidebarSection {
                            width: parent.width; title: "Notifications"; icon: "notifications"
                            summary: NotificationService.unreadCount > 0 ? NotificationService.unreadCount + " unread" : "All caught up"
                            objectName: "notifications"
                            expanded: root.expandedSection === "notifications"
                            onToggled: root.selectSection("notifications")
                            body: Component {
                                NotificationsPanel { sidebar: root; expanded: root.expandedSection === "notifications" }
                            }
                        }
                        SidebarSection {
                            width: parent.width; title: "Battery & power"; icon: BatteryService.getBatteryIcon()
                            summary: BatteryService.batteryAvailable ? BatteryService.batteryLevel + "% · " + BatteryService.batteryStatus : "Power profiles"
                            objectName: "battery"
                            expanded: root.expandedSection === "battery"
                            onToggled: root.selectSection("battery")
                            body: Component {
                                Column {
                                    spacing: 12
                                    BatteryDetail { width: parent.width }
                                    PluginContent {
                                        width: parent.width; sourcePlugin: "batteryLimit"; sidebar: root
                                        expanded: root.expandedSection === "battery"
                                    }
                                }
                            }
                        }
                        SidebarSection {
                            width: parent.width; title: "Codex Bar"; icon: "code"
                            summary: "AI usage & reset windows"
                            objectName: "codex"
                            expanded: root.expandedSection === "codex"
                            onToggled: root.selectSection("codex")
                            body: Component {
                                PluginContent {
                                    sourcePlugin: "codexBar"; sidebar: root; keepHeader: true
                                    expanded: root.expandedSection === "codex"
                                }
                            }
                        }
                    }
                }
                Item {
                    id: footer
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 24; anchors.rightMargin: 24
                    height: 32
                    Button {
                        id: powerButton
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        width: 92; height: 32
                        padding: 0; leftPadding: 0; rightPadding: 0
                        Accessible.name: "Power menu"
                        onClicked: root.launchPowerMenu()
                        background: Rectangle {
                            radius: Theme.cornerRadius
                            color: powerButton.hovered || powerButton.visualFocus ? Theme.surfaceContainerHigh : "transparent"
                            border.width: powerButton.visualFocus ? 1 : 0
                            border.color: Theme.primary
                        }
                        contentItem: Row {
                            spacing: 12
                            DankIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "power_settings_new"; size: 20; color: Theme.primary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Power"; font.pixelSize: 14; color: Theme.surfaceText
                            }
                        }
                    }
                    StyledText {
                        anchors.right: moreControls.left; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SUPER + N"
                        font.family: SettingsData.monoFontFamily
                        font.pixelSize: 10; font.letterSpacing: 1
                        color: Theme.surfaceVariantText
                    }
                    DankActionButton {
                        id: moreControls
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        iconName: "tune"; buttonSize: 32
                        Accessible.name: "More system controls"
                        onClicked: root.launchControlCenter()
                    }
                }
            }
        }
    }
}
