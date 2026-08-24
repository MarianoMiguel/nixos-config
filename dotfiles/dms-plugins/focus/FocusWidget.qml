import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "focus"

    readonly property string reminderPath: "/run/current-system/sw/bin/mariano-reminder"
    property var reminders: []
    property int selectedMinutes: 15
    property string reminderDraft: ""
    property string pendingReminderText: ""
    property string reminderError: ""
    property string mutationOperation: ""
    property bool clearConfirmation: false

    readonly property int reminderCount: reminders.length
    readonly property bool hasFocusState: SessionService.idleInhibited || SessionData.doNotDisturb || DisplayService.nightModeEnabled
    readonly property real focusViewportHeight: Math.max(260, Math.min(520, (parentScreen?.height ?? 900) - barThickness - 200))

    readonly property string pillIcon: {
        if (SessionService.idleInhibited)
            return "coffee";
        if (SessionData.doNotDisturb)
            return "notifications_off";
        if (DisplayService.nightModeEnabled)
            return "nightlight";
        if (reminderCount > 0)
            return "notifications_active";
        return "center_focus_strong";
    }

    readonly property string pillLabel: {
        if (SessionService.idleInhibited)
            return reminderCount > 0 ? "Awake · " + reminderCount : "Awake";
        if (SessionData.doNotDisturb)
            return reminderCount > 0 ? "Quiet · " + reminderCount : "Quiet";
        if (DisplayService.nightModeEnabled)
            return reminderCount > 0 ? "Night · " + reminderCount : "Night";
        return reminderCount > 0 ? String(reminderCount) : "";
    }

    readonly property color pillColor: hasFocusState || reminderCount > 0 ? Theme.primary : Theme.surfaceText

    function refreshReminders() {
        if (!listProcess.running) {
            listProcess.command = [reminderPath, "json"];
            listProcess.running = true;
        }
    }

    function setReminder(message) {
        const cleanMessage = message.trim();
        if (!cleanMessage || mutationProcess.running)
            return;
        reminderError = "";
        mutationOperation = "add";
        pendingReminderText = cleanMessage;
        mutationProcess.command = [reminderPath, "add", String(selectedMinutes), cleanMessage];
        mutationProcess.running = true;
    }

    function clearReminders() {
        if (reminderCount === 0 || mutationProcess.running)
            return;
        reminderError = "";
        mutationOperation = "clear";
        mutationProcess.command = [reminderPath, "clear"];
        mutationProcess.running = true;
    }

    function requestClearReminders() {
        if (!clearConfirmation) {
            clearConfirmation = true;
            clearConfirmationTimer.restart();
            return;
        }
        clearConfirmation = false;
        clearReminders();
    }

    function formatDue(epochSeconds) {
        const due = new Date(Number(epochSeconds) * 1000);
        const minutes = Math.max(1, Math.ceil((due.getTime() - Date.now()) / 60000));
        let relative;
        if (minutes < 60)
            relative = "in " + minutes + " min";
        else if (minutes < 1440)
            relative = "in " + Math.ceil(minutes / 60) + " hr";
        else
            relative = "in " + Math.ceil(minutes / 1440) + " days";
        return relative + " · " + Qt.formatTime(due, "HH:mm");
    }

    function isActivationKey(event) {
        return event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space;
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refreshReminders()
    }

    Timer {
        id: clearConfirmationTimer

        interval: 4000
        repeat: false
        onTriggered: root.clearConfirmation = false
    }

    Process {
        id: listProcess

        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "[]");
                    root.reminders = Array.isArray(parsed) ? parsed : [];
                    root.reminderError = "";
                } catch (error) {
                    root.reminderError = "The reminder list was not valid.";
                }
            }
        }

        stderr: StdioCollector {
            id: listError
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.reminderError = listError.text.trim() || "Could not read reminders.";
            }
        }
    }

    Process {
        id: mutationProcess

        running: false

        stderr: StdioCollector {
            id: mutationError
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.reminderError = mutationError.text.trim() || "The reminder change failed.";
                return;
            }
            if (root.mutationOperation === "add") {
                ToastService.showInfo("Reminder set");
                if (root.reminderDraft.trim() === root.pendingReminderText)
                    root.reminderDraft = "";
            } else {
                ToastService.showInfo("Reminders cleared");
            }
            root.pendingReminderText = "";
            root.mutationOperation = "";
            root.refreshReminders();
        }
    }

    Component.onCompleted: Qt.callLater(refreshReminders)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.pillIcon
                size: root.iconSize
                color: root.pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.pillLabel
                visible: text !== ""
                color: root.pillColor
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.pillIcon
            size: root.iconSize
            color: root.pillColor
        }
    }

    popoutWidth: 420

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Focus"
            detailsText: "Quiet controls and private local reminders"
            showCloseButton: true

            DankFlickable {
                id: focusScroll

                width: parent.width
                height: root.focusViewportHeight
                contentWidth: width
                contentHeight: focusColumn.implicitHeight
                interactive: contentHeight > height
                clip: true

                function revealItem(item) {
                    if (!item || contentHeight <= height)
                        return;
                    const position = item.mapToItem(focusColumn, 0, 0);
                    const itemTop = position.y - Theme.spacingS;
                    const itemBottom = position.y + item.height + Theme.spacingS;
                    if (itemTop < contentY)
                        contentY = Math.max(0, itemTop);
                    else if (itemBottom > contentY + height)
                        contentY = Math.min(contentHeight - height, itemBottom - height);
                }

                Column {
                    id: focusColumn

                    width: focusScroll.width - Theme.spacingS
                    spacing: Theme.spacingS

                    DankToggle {
                        id: stayAwakeToggle

                        width: parent.width
                        text: "Stay awake"
                        description: checked ? "Automatic locking and sleep are paused." : "Allow the normal lock and sleep schedule."
                        checked: SessionService.idleInhibited
                        activeFocusOnTab: true
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: text + (checked ? ", on" : ", off")
                        Accessible.checked: checked
                        onClicked: forceActiveFocus()
                        onToggled: SessionService.toggleIdleInhibit()
                        onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(stayAwakeToggle)
                        Keys.onPressed: event => {
                            if (root.isActivationKey(event)) {
                                handleClick();
                                event.accepted = true;
                            }
                        }

                        StyledRect {
                            anchors.fill: parent
                            z: 10
                            radius: Theme.cornerRadius
                            color: "transparent"
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: Theme.primary
                        }
                    }

                    DankToggle {
                        id: quietToggle

                        width: parent.width
                        text: "Silence notifications"
                        description: checked ? "Banners and notification sounds are silenced." : "Show notification banners and sounds."
                        checked: SessionData.doNotDisturb
                        activeFocusOnTab: true
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: text + (checked ? ", on" : ", off")
                        Accessible.checked: checked
                        onClicked: forceActiveFocus()
                        onToggled: SessionData.setDoNotDisturb(!SessionData.doNotDisturb)
                        onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(quietToggle)
                        Keys.onPressed: event => {
                            if (root.isActivationKey(event)) {
                                handleClick();
                                event.accepted = true;
                            }
                        }

                        StyledRect {
                            anchors.fill: parent
                            z: 10
                            radius: Theme.cornerRadius
                            color: "transparent"
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: Theme.primary
                        }
                    }

                    DankToggle {
                        id: nightLightToggle

                        width: parent.width
                        text: "Night Light"
                        description: checked ? "The display is using a warmer color temperature." : "Use the normal display color temperature."
                        checked: DisplayService.nightModeEnabled
                        activeFocusOnTab: true
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: text + (checked ? ", on" : ", off")
                        Accessible.checked: checked
                        onClicked: forceActiveFocus()
                        onToggled: DisplayService.toggleNightMode()
                        onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(nightLightToggle)
                        Keys.onPressed: event => {
                            if (root.isActivationKey(event)) {
                                handleClick();
                                event.accepted = true;
                            }
                        }

                        StyledRect {
                            anchors.fill: parent
                            z: 10
                            radius: Theme.cornerRadius
                            color: "transparent"
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: Theme.primary
                        }
                    }

                    StyledText {
                        topPadding: Theme.spacingS
                        text: "Set a reminder"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }

                    DankTextField {
                        id: reminderField

                        width: parent.width
                        text: root.reminderDraft
                        placeholderText: "What should I remember?"
                        leftIconName: "edit_notifications"
                        showClearButton: true
                        maximumLength: 500
                        onTextEdited: root.reminderDraft = text
                        onAccepted: root.setReminder(text)
                        onFocusStateChanged: hasFocus => {
                            if (hasFocus)
                                focusScroll.revealItem(reminderField);
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        Repeater {
                            model: [
                                { "label": "5m", "minutes": 5 },
                                { "label": "15m", "minutes": 15 },
                                { "label": "30m", "minutes": 30 },
                                { "label": "1h", "minutes": 60 },
                                { "label": "2h", "minutes": 120 }
                            ]

                            DankButton {
                                id: durationButton
                                required property var modelData

                                text: modelData.label
                                buttonHeight: 36
                                horizontalPadding: Theme.spacingM
                                backgroundColor: root.selectedMinutes === modelData.minutes ? Theme.primary : Theme.buttonBg
                                textColor: root.selectedMinutes === modelData.minutes ? Theme.onPrimary : Theme.buttonText
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: "Reminder delay " + modelData.label
                                onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(durationButton)
                                onClicked: {
                                    forceActiveFocus();
                                    root.selectedMinutes = modelData.minutes;
                                }
                                Keys.onPressed: event => {
                                    if (root.isActivationKey(event)) {
                                        root.selectedMinutes = modelData.minutes;
                                        event.accepted = true;
                                    }
                                }

                                StyledRect {
                                    anchors.fill: parent
                                    z: 10
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: parent.activeFocus ? 2 : 0
                                    border.color: Theme.primary
                                }
                            }
                        }
                    }

                    DankButton {
                        id: setReminderButton

                        text: mutationProcess.running && root.mutationOperation === "add" ? "Setting…" : "Set reminder"
                        iconName: "add_alert"
                        enabled: reminderField.text.trim().length > 0 && !mutationProcess.running
                        backgroundColor: Theme.primary
                        textColor: Theme.onPrimary
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(setReminderButton)
                        onClicked: {
                            forceActiveFocus();
                            root.setReminder(reminderField.text);
                        }
                        Keys.onPressed: event => {
                            if (root.isActivationKey(event) && enabled) {
                                root.setReminder(reminderField.text);
                                event.accepted = true;
                            }
                        }

                        StyledRect {
                            anchors.fill: parent
                            z: 10
                            radius: parent.radius
                            color: "transparent"
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: Theme.primary
                        }
                    }

                    StyledText {
                        width: parent.width
                        visible: root.reminderError !== ""
                        text: root.reminderError
                        textFormat: Text.PlainText
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        width: parent.width

                        StyledText {
                            width: parent.width - (clearButton.visible ? clearButton.width : 0)
                            text: root.reminderCount === 0 ? "No reminders scheduled" : root.reminderCount + (root.reminderCount === 1 ? " reminder" : " reminders")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankButton {
                            id: clearButton

                            visible: root.reminderCount > 0
                            text: root.clearConfirmation ? "Confirm clear" : "Clear all"
                            iconName: root.clearConfirmation ? "delete_forever" : "delete_sweep"
                            buttonHeight: 36
                            enabled: !mutationProcess.running
                            backgroundColor: root.clearConfirmation ? Theme.error : Theme.buttonBg
                            textColor: root.clearConfirmation ? Theme.surface : Theme.buttonText
                            activeFocusOnTab: visible
                            Accessible.role: Accessible.Button
                            Accessible.name: text
                            onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(clearButton)
                            onClicked: {
                                forceActiveFocus();
                                root.requestClearReminders();
                            }
                            Keys.onPressed: event => {
                                if (root.isActivationKey(event) && enabled) {
                                    root.requestClearReminders();
                                    event.accepted = true;
                                }
                            }

                            StyledRect {
                                anchors.fill: parent
                                z: 10
                                radius: parent.radius
                                color: "transparent"
                                border.width: parent.activeFocus ? 2 : 0
                                border.color: Theme.primary
                            }
                        }
                    }

                    Repeater {
                        model: root.reminders.slice(0, 4)

                        StyledRect {
                            required property var modelData

                            width: parent.width
                            height: reminderColumn.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                id: reminderColumn

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingXS

                                StyledText {
                                    width: parent.width
                                    text: modelData.message || "Reminder"
                                    textFormat: Text.PlainText
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: root.formatDue(modelData.due)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: root.reminderCount > 4
                        text: "+ " + (root.reminderCount - 4) + " more"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}
