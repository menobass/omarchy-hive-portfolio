import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Portfolio overlay: totals hero, add-account field and one card per account.
// Click the scrim or press Escape to close.
Item {
    id: root
    property bool opened: false
    property var host: null
    property var snapshot: null
    property var accountNames: []
    property string error: ""
    property bool loading: false
    property string formError: ""
    property var prefs: ({})
    property var mutedNames: []
    property bool showSettings: false

    function isMuted(name) { return mutedNames.indexOf(name) >= 0 }
    function setPref(key, value) { if (host) host.setPref(key, value) }

    // Palette: surfaces and text follow the theme; the three token colors are fixed.
    readonly property color textColor: Color.popups.text
    readonly property color mutedColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.6)
    readonly property color hairline: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)
    readonly property color cardFill: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.05)
    readonly property color hiveColor: "#f0645a"
    readonly property color hbdColor: "#4fd6a5"
    readonly property color warnColor: "#e6b84a"
    readonly property int radius: Math.max(8, Style.cornerRadius)

    function open() { root.formError = ""; root.showSettings = false; root.opened = true }
    function close() { root.opened = false }
    function toggle() { root.opened ? root.close() : root.open() }

    function details(name) {
        var list = snapshot ? snapshot.accounts : []
        for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
        return null
    }

    function isMissing(name) {
        return snapshot ? snapshot.missing.indexOf(name) >= 0 : false
    }

    function submit() {
        if (!host) return
        var msg = host.addAccount(addField.text)
        formError = msg
        if (msg === "") addField.text = ""
    }

    function updatedText() {
        if (!snapshot) return "—"
        return Qt.formatTime(new Date(snapshot.fetchedAt), "HH:mm")
    }

    // ---- small building blocks -------------------------------------------

    component Caption: Text {
        color: root.mutedColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
    }

    component Stat: Item {
        id: st
        property string label
        property string value
        property color tone: root.textColor
        Layout.fillWidth: true
        Layout.preferredWidth: 100
        implicitWidth: Math.max(cap.implicitWidth, val.implicitWidth)
        implicitHeight: cap.implicitHeight + val.implicitHeight + 2
        Caption { id: cap; text: st.label; width: parent.width; elide: Text.ElideRight }
        Text {
            id: val
            y: cap.implicitHeight + 2
            width: parent.width
            text: st.value
            color: st.tone
            elide: Text.ElideRight
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.subtitle
        }
    }

    component SettingRow: RowLayout {
        id: sr
        property string title
        property string hint: ""
        property bool isSwitch: true
        property bool checked: false
        property int value: 0
        property int from: 0
        property int to: 100
        property int step: 1
        property string unit: ""
        signal toggled()
        signal changed(int value)

        Layout.fillWidth: true
        spacing: Style.space(10)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: sr.title
                color: root.textColor
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                visible: sr.hint !== ""
                text: sr.hint
                color: root.mutedColor
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }
        ToggleSwitch {
            visible: sr.isSwitch
            checked: sr.checked
            onToggled: sr.toggled()
        }
        RowLayout {
            visible: !sr.isSwitch
            spacing: Style.space(4)
            IconButton {
                glyph: "−"
                enabledButton: sr.value > sr.from
                onClicked: sr.changed(Math.max(sr.from, sr.value - sr.step))
            }
            Text {
                text: sr.value + sr.unit
                color: root.textColor
                font.family: Style.font.family
                font.bold: true
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: Style.space(52)
            }
            IconButton {
                glyph: "+"
                enabledButton: sr.value < sr.to
                onClicked: sr.changed(Math.min(sr.to, sr.value + sr.step))
            }
        }
    }

    component IconButton: Rectangle {
        id: ib
        property string glyph
        property color tone: root.mutedColor
        property color hoverTone: root.textColor
        property bool enabledButton: true
        property alias glyphRotation: glyphText.rotation
        signal clicked()
        implicitWidth: Style.space(26)
        implicitHeight: Style.space(26)
        radius: width / 2
        color: area.containsMouse && enabledButton ? root.hairline : "transparent"
        opacity: enabledButton ? 1 : 0.25
        Text {
            id: glyphText
            anchors.centerIn: parent
            text: ib.glyph
            color: area.containsMouse && ib.enabledButton ? ib.hoverTone : ib.tone
            font.family: Style.font.family
            font.pixelSize: Style.font.title
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: ib.enabledButton
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    component ManaBar: ColumnLayout {
        property string label
        property real percent
        property real hours
        property color tone
        readonly property bool low: percent < 25
        spacing: 4
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        RowLayout {
            Layout.fillWidth: true
            Caption { text: parent.parent.label; Layout.fillWidth: true }
            Text {
                text: parent.parent.percent.toFixed(1) + "%"
                color: parent.parent.low ? root.warnColor : root.textColor
                font.family: Style.font.family
                font.bold: true
                font.pixelSize: Style.font.body
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(6)
            radius: height / 2
            color: root.hairline
            Rectangle {
                width: Math.max(parent.height, parent.width * Math.min(100, parent.parent.percent) / 100)
                height: parent.height
                radius: height / 2
                color: parent.parent.low ? root.warnColor : parent.parent.tone
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            text: Model.formatDuration(parent.hours)
            color: root.mutedColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }

    // ---- window ----------------------------------------------------------

    PanelWindow {
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hive-portfolio-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()

            Rectangle {
                id: card
                readonly property int pad: Style.space(18)
                anchors.centerIn: parent
                width: Math.min(Style.space(500), parent.width - Style.space(40))
                height: Math.min(parent.height * 0.88, content.implicitHeight + pad * 2)
                radius: root.radius + 4
                color: Color.popups.background
                border.width: 1
                border.color: root.hairline

                MouseArea { anchors.fill: parent } // swallow clicks so the scrim doesn't close us

                ColumnLayout {
                    id: content
                    x: card.pad
                    y: card.pad
                    width: card.width - card.pad * 2
                    height: card.height - card.pad * 2
                    spacing: Style.space(12)

                    // Totals hero
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: hero.implicitHeight + Style.space(28)
                        radius: root.radius
                        color: root.cardFill
                        border.width: 1
                        border.color: root.hairline

                        ColumnLayout {
                            id: hero
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(14) }
                            spacing: Style.space(10)

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    spacing: 2
                                    RowLayout {
                                        spacing: Style.space(8)
                                        Image {
                                            source: Qt.resolvedUrl("assets/hive-logo.png")
                                            sourceSize.width: 64
                                            sourceSize.height: 64
                                            Layout.preferredWidth: Style.space(22)
                                            Layout.preferredHeight: Style.space(22)
                                            smooth: true
                                            mipmap: true
                                        }
                                        Caption { text: "Hive portfolio" }
                                    }
                                    Text {
                                        text: Model.formatUsd(root.snapshot ? root.snapshot.totals.usd : 0)
                                        color: root.textColor
                                        font.family: Style.font.family
                                        font.bold: true
                                        font.pixelSize: Style.font.displayLarge
                                    }
                                    Text {
                                        text: root.accountNames.length + (root.accountNames.length === 1 ? " account" : " accounts")
                                            + " · updated " + root.updatedText()
                                        color: root.mutedColor
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                    }
                                }
                                Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }
                                IconButton {
                                    glyph: "⚙"
                                    Layout.alignment: Qt.AlignTop
                                    tone: root.showSettings ? root.textColor : root.mutedColor
                                    onClicked: root.showSettings = !root.showSettings
                                }
                                IconButton {
                                    glyph: "↻"
                                    Layout.alignment: Qt.AlignTop
                                    enabledButton: !root.loading
                                    onClicked: if (root.host) root.host.refresh()
                                    RotationAnimator on glyphRotation {
                                        from: 0; to: 360; duration: 900
                                        loops: Animation.Infinite
                                        running: root.loading && root.opened
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.hairline }

                            RowLayout {
                                Layout.fillWidth: true
                                Stat { label: "Hive Power"; value: Model.formatNumber(root.snapshot ? root.snapshot.totals.hivePower : 0, 0) }
                                Stat { label: "HIVE"; value: Model.formatNumber(root.snapshot ? root.snapshot.totals.hive : 0, 0); tone: root.hiveColor }
                                Stat { label: "HBD"; value: Model.formatNumber(root.snapshot ? root.snapshot.totals.hbd : 0, 0); tone: root.hbdColor }
                            }

                            Text {
                                visible: root.snapshot !== null
                                text: root.snapshot ? "HIVE " + Model.formatUsd(root.snapshot.hiveUsd) + " · HBD " + Model.formatUsd(root.snapshot.hbdUsd) : ""
                                color: root.mutedColor
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                            }
                        }
                    }

                    Text {
                        visible: root.error !== ""
                        text: "Couldn't refresh: " + root.error
                        color: root.warnColor
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }

                    // Settings (all of it saved automatically)
                    Rectangle {
                        visible: root.showSettings
                        Layout.fillWidth: true
                        implicitHeight: settingsCol.implicitHeight + Style.space(28)
                        radius: root.radius
                        color: root.cardFill
                        border.width: 1
                        border.color: root.hairline

                        ColumnLayout {
                            id: settingsCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(14) }
                            spacing: Style.space(10)

                            Caption { text: "Settings" }

                            SettingRow {
                                title: "Notifications"
                                hint: "Desktop notification when voting power is about to fill or is full. Mute single accounts with their bell."
                                checked: root.prefs.notify === true
                                onToggled: root.setPref("notify", !checked)
                            }
                            SettingRow {
                                title: "Heads-up before full"
                                hint: "Minutes before 100% to warn you. 0 turns the heads-up off."
                                isSwitch: false
                                value: root.prefs.warnMinutes !== undefined ? root.prefs.warnMinutes : 30
                                from: 0; to: 120; step: 5; unit: " min"
                                onChanged: function(v) { root.setPref("warnMinutes", v) }
                            }
                            SettingRow {
                                title: "Pulse when voting power is full"
                                hint: "Orange ring on the avatar and logo in the bar."
                                checked: root.prefs.alerts === true
                                onToggled: root.setPref("alerts", !checked)
                            }
                            SettingRow {
                                title: "Show full accounts more often"
                                hint: "Accounts at 100% take every other slot in the bar rotation."
                                checked: root.prefs.prioritizeAlerts === true
                                onToggled: root.setPref("prioritizeAlerts", !checked)
                            }
                            SettingRow {
                                title: "Switch avatar every"
                                isSwitch: false
                                value: root.prefs.rotateSeconds !== undefined ? root.prefs.rotateSeconds : 10
                                from: 3; to: 60; step: 1; unit: " s"
                                onChanged: function(v) { root.setPref("rotateSeconds", v) }
                            }
                            SettingRow {
                                title: "Refresh data every"
                                isSwitch: false
                                value: root.prefs.refreshMinutes !== undefined ? root.prefs.refreshMinutes : 5
                                from: 1; to: 60; step: 1; unit: " min"
                                onChanged: function(v) { root.setPref("refreshMinutes", v) }
                            }
                        }
                    }

                    // Add account
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(8)

                        TextField {
                            id: addField
                            Layout.fillWidth: true
                            placeholderText: "Track a Hive account (e.g. @alice)"
                            focus: true
                            onAccepted: root.submit()
                            onTextChanged: root.formError = ""
                            Keys.onEscapePressed: root.close()
                        }
                        Button {
                            text: "Add"
                            bordered: true
                            focusable: true
                            onClicked: root.submit()
                        }
                    }

                    Text {
                        visible: root.formError !== ""
                        text: root.formError
                        color: Color.urgent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }

                    Text {
                        visible: root.accountNames.length === 0
                        text: "No accounts yet. Type a Hive username above and press Enter."
                        color: root.mutedColor
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Account cards
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: Math.min(accountColumn.implicitHeight, Style.space(120))
                        Layout.preferredHeight: accountColumn.implicitHeight
                        contentHeight: accountColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: accountColumn
                            width: parent.width
                            spacing: Style.space(10)

                            Repeater {
                                model: root.accountNames
                                delegate: Rectangle {
                                    id: acct
                                    required property string modelData
                                    required property int index
                                    property var d: root.details(modelData)
                                    property bool missing: root.isMissing(modelData)
                                    readonly property real savings: d ? d.hiveSavings + d.hbdSavings : 0
                                    readonly property real rewards: d ? d.rewardHive + d.rewardHbd + d.rewardHp : 0

                                    Layout.fillWidth: true
                                    implicitHeight: body.implicitHeight + Style.space(24)
                                    radius: root.radius
                                    color: root.cardFill
                                    border.width: 1
                                    border.color: root.hairline

                                    ColumnLayout {
                                        id: body
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(12) }
                                        spacing: Style.space(10)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(10)
                                            AccountAvatar {
                                                name: acct.modelData
                                                size: Style.space(38)
                                                hasRewards: acct.rewards > 0
                                                alert: acct.d !== null && acct.d.votingPower >= 99.9 && !root.isMuted(acct.modelData)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    text: "@" + acct.modelData
                                                    color: root.textColor
                                                    font.family: Style.font.family
                                                    font.bold: true
                                                    font.pixelSize: Style.font.subtitle
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: acct.missing ? "account not found" : ((acct.d ? Model.formatUsd(acct.d.usd) : "loading…") + (root.isMuted(acct.modelData) ? "  ·  alerts off" : ""))
                                                    color: acct.missing ? root.warnColor : root.mutedColor
                                                    font.family: Style.font.family
                                                    font.pixelSize: Style.font.bodySmall
                                                }
                                            }
                                            IconButton {
                                                readonly property bool muted: root.isMuted(acct.modelData)
                                                glyph: muted ? "󰂛" : "󰂚"
                                                tone: muted ? root.mutedColor : root.hbdColor
                                                hoverTone: root.textColor
                                                onClicked: if (root.host) root.host.toggleMute(acct.modelData)
                                            }
                                            IconButton {
                                                glyph: "↑"
                                                enabledButton: acct.index > 0
                                                onClicked: if (root.host) root.host.moveAccount(acct.modelData, -1)
                                            }
                                            IconButton {
                                                glyph: "↓"
                                                enabledButton: acct.index < root.accountNames.length - 1
                                                onClicked: if (root.host) root.host.moveAccount(acct.modelData, 1)
                                            }
                                            IconButton {
                                                glyph: "×"
                                                hoverTone: Color.urgent
                                                onClicked: if (root.host) root.host.removeAccount(acct.modelData)
                                            }
                                        }

                                        RowLayout {
                                            visible: acct.d !== null
                                            Layout.fillWidth: true
                                            spacing: Style.space(14)
                                            ManaBar {
                                                label: "Voting power"
                                                percent: acct.d ? acct.d.votingPower : 0
                                                hours: acct.d ? acct.d.votingFullInHours : 0
                                                tone: root.hiveColor
                                            }
                                            ManaBar {
                                                label: "Resource credits"
                                                percent: acct.d ? acct.d.rcPercent : 0
                                                hours: acct.d ? acct.d.rcFullInHours : 0
                                                tone: root.hbdColor
                                            }
                                        }

                                        Rectangle {
                                            visible: acct.d !== null
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 1
                                            color: root.hairline
                                        }

                                        RowLayout {
                                            visible: acct.d !== null
                                            Layout.fillWidth: true
                                            Stat { label: "HIVE"; value: acct.d ? Model.formatNumber(acct.d.hive) : ""; tone: root.hiveColor }
                                            Stat { label: "Hive Power"; value: acct.d ? Model.formatNumber(acct.d.hivePower) : "" }
                                            Stat { label: "HBD"; value: acct.d ? Model.formatNumber(acct.d.hbd) : ""; tone: root.hbdColor }
                                        }

                                        RowLayout {
                                            visible: acct.savings > 0
                                            Layout.fillWidth: true
                                            Stat { label: "HIVE savings"; value: acct.d ? Model.formatNumber(acct.d.hiveSavings) : "" }
                                            Stat { label: "HBD savings"; value: acct.d ? Model.formatNumber(acct.d.hbdSavings) : "" }
                                            Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }
                                        }

                                        Rectangle {
                                            visible: acct.rewards > 0
                                            Layout.fillWidth: true
                                            implicitHeight: rewardCol.implicitHeight + Style.space(16)
                                            radius: root.radius
                                            color: Qt.rgba(root.warnColor.r, root.warnColor.g, root.warnColor.b, 0.1)
                                            border.width: 1
                                            border.color: Qt.rgba(root.warnColor.r, root.warnColor.g, root.warnColor.b, 0.4)
                                            ColumnLayout {
                                                id: rewardCol
                                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.space(8) }
                                                spacing: 2
                                                Caption { text: "Unclaimed rewards"; color: root.warnColor }
                                                Text {
                                                    text: acct.d ? Model.formatNumber(acct.d.rewardHive) + " HIVE · "
                                                        + Model.formatNumber(acct.d.rewardHp) + " HP · "
                                                        + Model.formatNumber(acct.d.rewardHbd) + " HBD" : ""
                                                    color: root.textColor
                                                    font.family: Style.font.family
                                                    font.pixelSize: Style.font.bodySmall
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
