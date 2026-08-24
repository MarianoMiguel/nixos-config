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
    property string scheduleMode: "relative"
    property int selectedQuickMinutes: 15
    property string relativeAmount: "15"
    property string relativeUnit: "minutes"
    property string exactDateDraft: ""
    property string exactTimeDraft: ""
    property string reminderDraft: ""
    property string pendingReminderText: ""
    property string reminderError: ""
    property string mutationOperation: ""
    property bool clearConfirmation: false

    readonly property int reminderCount: reminders.length
    readonly property bool hasFocusState: SessionService.idleInhibited || SessionData.doNotDisturb || DisplayService.nightModeEnabled
    readonly property bool scheduleValid: scheduleMode === "relative" ? relativeScheduleIsValid() : exactScheduleIsValid()
    readonly property real focusViewportHeight: Math.max(300, Math.min(620, (parentScreen?.height ?? 900) - barThickness - 140))

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

    function relativeMaximum() {
        switch (relativeUnit) {
        case "minutes": return 5256000;
        case "hours": return 87600;
        case "days": return 3650;
        case "weeks": return 520;
        case "months": return 120;
        default: return 0;
        }
    }

    function parsedRelativeAmount() {
        const clean = relativeAmount.trim();
        if (!/^[0-9]+$/.test(clean))
            return 0;
        return Number(clean);
    }

    function relativeScheduleIsValid() {
        const amount = parsedRelativeAmount();
        return amount >= 1 && amount <= relativeMaximum();
    }

    function exactDateValue() {
        const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(exactDateDraft.trim());
        const timeMatch = /^(\d{2}):(\d{2})$/.exec(exactTimeDraft.trim());
        if (!dateMatch || !timeMatch)
            return null;
        const value = new Date(Number(dateMatch[1]), Number(dateMatch[2]) - 1,
                               Number(dateMatch[3]), Number(timeMatch[1]),
                               Number(timeMatch[2]), 0, 0);
        if (value.getFullYear() !== Number(dateMatch[1])
                || value.getMonth() !== Number(dateMatch[2]) - 1
                || value.getDate() !== Number(dateMatch[3])
                || value.getHours() !== Number(timeMatch[1])
                || value.getMinutes() !== Number(timeMatch[2]))
            return null;
        return value;
    }

    function exactScheduleIsValid() {
        const value = exactDateValue();
        return value !== null && value.getTime() > Date.now();
    }

    function prepareExactSchedule() {
        if (exactScheduleIsValid())
            return;
        const target = new Date(Date.now() + 60 * 60 * 1000);
        target.setMinutes(Math.ceil(target.getMinutes() / 5) * 5, 0, 0);
        exactDateDraft = Qt.formatDate(target, "yyyy-MM-dd");
        exactTimeDraft = Qt.formatTime(target, "HH:mm");
    }

    function selectQuickReminder(minutes, amount, unit) {
        scheduleMode = "relative";
        selectedQuickMinutes = minutes;
        relativeAmount = String(amount);
        relativeUnit = unit;
        reminderError = "";
    }

    function scheduleSummary() {
        if (scheduleMode === "at") {
            const exact = exactDateValue();
            return exactScheduleIsValid()
                ? "Due " + Qt.formatDateTime(exact, "ddd d MMM · HH:mm")
                : "Choose a valid future date and time.";
        }
        if (!relativeScheduleIsValid())
            return "Enter a valid duration.";
        const amount = parsedRelativeAmount();
        const singular = relativeUnit.slice(0, -1);
        const target = new Date();
        switch (relativeUnit) {
        case "minutes": target.setMinutes(target.getMinutes() + amount); break;
        case "hours": target.setHours(target.getHours() + amount); break;
        case "days": target.setDate(target.getDate() + amount); break;
        case "weeks": target.setDate(target.getDate() + amount * 7); break;
        case "months": target.setMonth(target.getMonth() + amount); break;
        }
        return "In " + amount + " " + (amount === 1 ? singular : relativeUnit)
            + " · " + Qt.formatDateTime(target, "ddd d MMM · HH:mm");
    }

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
        if (!scheduleValid) {
            reminderError = scheduleMode === "at"
                ? "Choose a valid future date and time."
                : "Enter a valid duration and unit.";
            return;
        }
        reminderError = "";
        mutationOperation = "add";
        pendingReminderText = cleanMessage;
        mutationProcess.command = scheduleMode === "at"
            ? [reminderPath, "at", exactDateDraft.trim(), exactTimeDraft.trim(), cleanMessage]
            : [reminderPath, "in", relativeAmount.trim(), relativeUnit, cleanMessage];
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
        else if (minutes < 20160)
            relative = "in " + Math.ceil(minutes / 1440) + " days";
        else if (minutes < 86400)
            relative = "in " + Math.ceil(minutes / 10080) + " weeks";
        else
            relative = "in " + Math.ceil(minutes / 43200) + " months";
        return relative + " · " + (minutes < 1440
            ? Qt.formatTime(due, "HH:mm")
            : Qt.formatDateTime(due, "ddd d MMM · HH:mm"));
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

    Component.onCompleted: {
        prepareExactSchedule();
        Qt.callLater(refreshReminders);
    }

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
                        id: scheduleModeRow

                        width: parent.width
                        spacing: Theme.spacingXS

                        Repeater {
                            model: [
                                { "label": "In a duration", "mode": "relative", "icon": "schedule" },
                                { "label": "On a date", "mode": "at", "icon": "event" }
                            ]

                            DankButton {
                                id: scheduleModeButton
                                required property var modelData
                                readonly property bool selected: root.scheduleMode === modelData.mode

                                text: modelData.label
                                iconName: modelData.icon
                                width: (scheduleModeRow.width - scheduleModeRow.spacing) / 2
                                buttonHeight: 40
                                horizontalPadding: Theme.spacingM
                                backgroundColor: selected ? Theme.primary : Theme.surfaceContainerHighest
                                textColor: selected ? Theme.onPrimary : Theme.surfaceText
                                border.width: selected ? 0 : 1
                                border.color: Theme.outlineStrong
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: "Schedule " + modelData.label
                                Accessible.checked: selected
                                onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(scheduleModeButton)
                                onClicked: {
                                    forceActiveFocus();
                                    root.scheduleMode = modelData.mode;
                                    if (modelData.mode === "at")
                                        root.prepareExactSchedule();
                                    root.reminderError = "";
                                }
                                Keys.onPressed: event => {
                                    if (root.isActivationKey(event)) {
                                        root.scheduleMode = modelData.mode;
                                        if (modelData.mode === "at")
                                            root.prepareExactSchedule();
                                        root.reminderError = "";
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

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.scheduleMode === "relative"

                        StyledText {
                            text: "Quick choices"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        Flow {
                            id: quickChoiceFlow

                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: [
                                    { "label": "5m", "minutes": 5, "amount": 5, "unit": "minutes" },
                                    { "label": "15m", "minutes": 15, "amount": 15, "unit": "minutes" },
                                    { "label": "1h", "minutes": 60, "amount": 1, "unit": "hours" },
                                    { "label": "24h", "minutes": 1440, "amount": 24, "unit": "hours" },
                                    { "label": "1 week", "minutes": 10080, "amount": 1, "unit": "weeks" }
                                ]

                                DankButton {
                                    id: quickChoiceButton
                                    required property var modelData
                                    readonly property bool selected: root.selectedQuickMinutes === modelData.minutes

                                    text: modelData.label
                                    buttonHeight: 36
                                    horizontalPadding: Theme.spacingM
                                    backgroundColor: selected ? Theme.primary : Theme.surfaceContainerHighest
                                    textColor: selected ? Theme.onPrimary : Theme.surfaceText
                                    border.width: selected ? 0 : 1
                                    border.color: Theme.outlineStrong
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Remind me in " + modelData.label
                                    Accessible.checked: selected
                                    onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(quickChoiceButton)
                                    onClicked: {
                                        forceActiveFocus();
                                        root.selectQuickReminder(modelData.minutes, modelData.amount, modelData.unit);
                                    }
                                    Keys.onPressed: event => {
                                        if (root.isActivationKey(event)) {
                                            root.selectQuickReminder(modelData.minutes, modelData.amount, modelData.unit);
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
                    }

                    StyledRect {
                        width: parent.width
                        height: relativeScheduleColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.scheduleMode === "relative"
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.width: 1
                        border.color: Theme.outlineMedium

                        Column {
                            id: relativeScheduleColumn

                            x: Theme.spacingM
                            y: Theme.spacingM
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS

                            StyledText {
                                text: "Custom duration"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }

                            DankTextField {
                                id: durationAmountField

                                width: parent.width
                                text: root.relativeAmount
                                labelText: "Amount"
                                placeholderText: "48"
                                leftIconName: "hourglass_top"
                                maximumLength: 7
                                validator: IntValidator { bottom: 1; top: 5256000 }
                                onTextEdited: {
                                    root.relativeAmount = text;
                                    root.selectedQuickMinutes = 0;
                                    root.reminderError = "";
                                }
                                onAccepted: root.setReminder(reminderField.text)
                                onFocusStateChanged: hasFocus => {
                                    if (hasFocus)
                                        focusScroll.revealItem(durationAmountField);
                                }
                            }

                            Flow {
                                id: durationUnitFlow

                                width: parent.width
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: ["minutes", "hours", "days", "weeks", "months"]

                                    DankButton {
                                        id: durationUnitButton
                                        required property string modelData
                                        readonly property bool selected: root.relativeUnit === modelData

                                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                        buttonHeight: 34
                                        horizontalPadding: Theme.spacingS
                                        backgroundColor: selected ? Theme.primary : Theme.surfaceContainerHighest
                                        textColor: selected ? Theme.onPrimary : Theme.surfaceText
                                        border.width: selected ? 0 : 1
                                        border.color: Theme.outlineStrong
                                        activeFocusOnTab: true
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Duration unit " + modelData
                                        Accessible.checked: selected
                                        onActiveFocusChanged: if (activeFocus) focusScroll.revealItem(durationUnitButton)
                                        onClicked: {
                                            forceActiveFocus();
                                            root.relativeUnit = modelData;
                                            root.selectedQuickMinutes = 0;
                                            root.reminderError = "";
                                        }
                                        Keys.onPressed: event => {
                                            if (root.isActivationKey(event)) {
                                                root.relativeUnit = modelData;
                                                root.selectedQuickMinutes = 0;
                                                root.reminderError = "";
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
                        }
                    }

                    StyledRect {
                        width: parent.width
                        height: exactScheduleColumn.implicitHeight + Theme.spacingM * 2
                        visible: root.scheduleMode === "at"
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.width: 1
                        border.color: Theme.outlineMedium

                        Column {
                            id: exactScheduleColumn

                            x: Theme.spacingM
                            y: Theme.spacingM
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS

                            StyledText {
                                text: "Specific date and time"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }

                            Row {
                                id: exactFieldsRow

                                width: parent.width
                                spacing: Theme.spacingS

                                DankTextField {
                                    id: exactDateField

                                    width: Math.floor((exactFieldsRow.width - exactFieldsRow.spacing) * 0.62)
                                    text: root.exactDateDraft
                                    labelText: "Date"
                                    placeholderText: "YYYY-MM-DD"
                                    leftIconName: "calendar_today"
                                    maximumLength: 10
                                    onTextEdited: {
                                        root.exactDateDraft = text;
                                        root.reminderError = "";
                                    }
                                    onAccepted: root.setReminder(reminderField.text)
                                    onFocusStateChanged: hasFocus => {
                                        if (hasFocus)
                                            focusScroll.revealItem(exactDateField);
                                    }
                                }

                                DankTextField {
                                    id: exactTimeField

                                    width: exactFieldsRow.width - exactDateField.width - exactFieldsRow.spacing
                                    text: root.exactTimeDraft
                                    labelText: "Time"
                                    placeholderText: "HH:MM"
                                    leftIconName: "schedule"
                                    maximumLength: 5
                                    onTextEdited: {
                                        root.exactTimeDraft = text;
                                        root.reminderError = "";
                                    }
                                    onAccepted: root.setReminder(reminderField.text)
                                    onFocusStateChanged: hasFocus => {
                                        if (hasFocus)
                                            focusScroll.revealItem(exactTimeField);
                                    }
                                }
                            }
                        }
                    }

                    StyledRect {
                        width: parent.width
                        height: scheduleSummaryRow.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.primaryContainer

                        Row {
                            id: scheduleSummaryRow

                            x: Theme.spacingM
                            y: Theme.spacingM
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS

                            DankIcon {
                                name: root.scheduleValid ? "notifications_active" : "warning"
                                size: Theme.iconSize
                                color: root.scheduleValid ? Theme.primary : Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                width: parent.width - Theme.iconSize - parent.spacing
                                text: root.scheduleSummary()
                                textFormat: Text.PlainText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    DankButton {
                        id: setReminderButton

                        text: mutationProcess.running && root.mutationOperation === "add" ? "Setting…" : "Set reminder"
                        iconName: "add_alert"
                        width: parent.width
                        buttonHeight: 42
                        enabled: reminderField.text.trim().length > 0 && root.scheduleValid && !mutationProcess.running
                        opacity: 1
                        backgroundColor: enabled ? Theme.primary : Theme.surfaceContainerHighest
                        textColor: enabled ? Theme.onPrimary : Theme.surfaceVariantText
                        border.width: enabled ? 0 : 1
                        border.color: Theme.outlineStrong
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
