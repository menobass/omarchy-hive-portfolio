import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget for Hive portfolio. Shows a concise summary; click opens a detail panel.
BarWidget {
    id: root
    moduleName: "io.github.menobass.hive-portfolio"

    implicitWidth: button.implicitWidth
    width: implicitWidth
    implicitHeight: button.implicitHeight

    // Accounts are managed from the panel and stored in accountsPath. The
    // "accounts" entry in shell.json only seeds the list the first time.
    readonly property var accountsSetting: setting("accounts", [])
    readonly property string accountsPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/hive-portfolio-accounts.json"
    property var accountNames: []
    property bool accountsLoaded: false

    // Everything the user can change lives in the panel and is saved to
    // accountsPath next to the account list. shell.json values only act as
    // the defaults for settings that were never changed in the panel.
    readonly property var defaults: ({
        notify: setting("notify", true) !== false,
        alerts: setting("alerts", true) !== false,
        prioritizeAlerts: setting("prioritizeAlerts", true) !== false,
        warnMinutes: Math.max(0, setting("warnMinutes", 30)),
        rotateSeconds: Math.max(3, setting("rotateSeconds", 10)),
        refreshMinutes: Math.max(1, Math.round(setting("refreshInterval", 300) / 60))
    })
    property var overrides: ({})
    property var mutedNames: []   // accounts with alerts (notification, pulse, priority) turned off
    readonly property var prefs: {
        var p = {}
        for (var k in defaults) p[k] = overrides[k] !== undefined ? overrides[k] : defaults[k]
        return p
    }
    readonly property int refreshInterval: prefs.refreshMinutes * 60 // seconds

    function isMuted(name) { return mutedNames.indexOf(name) >= 0 }

    function setPref(key, value) {
        var o = {}
        for (var k in overrides) o[k] = overrides[k]
        o[key] = value
        overrides = o
        saveAccounts()
        if (key === "notify" || key === "warnMinutes" || key === "alerts") checkAlerts()
    }

    function toggleMute(name) {
        mutedNames = isMuted(name) ? mutedNames.filter(function(n) { return n !== name }) : mutedNames.concat([name])
        saveAccounts()
        checkAlerts()
    }

    property var snapshot: null
    property bool loading: false
    property string error: ""

    // --- rotation: one account at a time in the bar -----------------------
    readonly property int rotateSeconds: prefs.rotateSeconds
    readonly property bool alertsEnabled: prefs.alerts
    property int rotIndex: 0
    // Full VP that is worth shouting about: alerts on and the account not muted.
    function isFull(a) { return a.votingPower >= fullThreshold && !isMuted(a.name) }
    readonly property bool prioritizeAlerts: prefs.prioritizeAlerts
    readonly property real fullThreshold: 99.9
    readonly property var barAccounts: snapshot ? snapshot.accounts : []

    // Order the bar cycles through. Accounts with full VP are interleaved
    // between the others (X a X b X c ...) so they show every other slot
    // instead of once per lap. With only full accounts, they just alternate.
    readonly property var rotation: {
        var all = barAccounts
        if (!prioritizeAlerts || !alertsEnabled) return all
        var hot = [], rest = []
        for (var i = 0; i < all.length; i++) (isFull(all[i]) ? hot : rest).push(all[i])
        if (hot.length === 0 || rest.length === 0) return all
        var out = []
        for (var j = 0; j < rest.length; j++) {
            out.push(hot[j % hot.length])
            out.push(rest[j])
        }
        return out
    }
    readonly property var current: rotation.length > 0 ? rotation[rotIndex % rotation.length] : null
    readonly property bool currentFull: alertsEnabled && current !== null && isFull(current)
    readonly property bool currentRewards: current !== null && (current.rewardHive + current.rewardHbd + current.rewardHp) > 0
    readonly property string currentName: current ? current.name : ""
    readonly property var fullNames: {
        var out = []
        if (!alertsEnabled) return out
        for (var i = 0; i < barAccounts.length; i++) if (isFull(barAccounts[i])) out.push(barAccounts[i].name)
        return out
    }
    readonly property bool anyFull: fullNames.length > 0
    readonly property string vpText: current ? Math.round(current.votingPower) + "%" : (accountsLoaded && accountNames.length === 0 ? "add" : (error !== "" ? "err" : "…"))

    readonly property string tooltip: {
        if (!snapshot) return error !== "" ? error : "Loading…"
        var lines = []
        if (fullNames.length > 0) lines.push("⚠ Voting power full, go vote: " + fullNames.map(function(n) { return "@" + n }).join(", "))
        lines.push("Portfolio " + Model.formatUsd(snapshot.totals.usd))
        for (var i = 0; i < barAccounts.length; i++) {
            var a = barAccounts[i]
            lines.push("@" + a.name + "  VP " + Math.round(a.votingPower) + "%"
                + ((a.rewardHive + a.rewardHbd + a.rewardHp) > 0 ? "  · rewards to claim" : ""))
        }
        return lines.join("\n")
    }


    // --- notifications ---------------------------------------------------
    // One desktop notification when an account's voting power is about to
    // fill (warnMinutes before) and one when it is full. What was already
    // announced is kept in a small state file so shell restarts don't repeat
    // themselves; an account is re-armed once its VP drops below 99%.
    readonly property bool notifyEnabled: prefs.notify
    readonly property int warnMinutes: prefs.warnMinutes
    readonly property string statePath: (Quickshell.env("HOME") || "") + "/.config/omarchy/hive-portfolio-state.json"
    readonly property string logoPath: decodeURIComponent(Qt.resolvedUrl("assets/hive-logo.png").toString().replace(/^file:\/\//, ""))
    property var notified: ({})
    property bool stateLoaded: false

    function sendNotification(title, body) {
        Quickshell.execDetached({
            command: ["notify-send", "--app-name=Hive Portfolio", "--icon=" + root.logoPath,
                      "--urgency=normal", title, body]
        })
    }

    function names(list) {
        return list.map(function(n) { return "@" + n }).join(", ")
    }

    // There is one bar (and so one widget instance) per monitor; only the
    // first instance notifies, otherwise every alert would be sent once per screen.
    function isNotifier() {
        if (!bar || typeof bar.moduleWidgets !== "function") return true
        var all = bar.moduleWidgets(moduleName)
        return all.length === 0 || all[0] === root
    }

    function checkAlerts() {
        if (!stateLoaded || !snapshot || !notifyEnabled || !isNotifier()) return
        var state = {}, changed = false
        var fullNew = [], soonNew = []
        var list = snapshot.accounts
        for (var i = 0; i < list.length; i++) {
            var a = list[i], prev = notified[a.name]
            var next = prev
            if (a.votingPower < 99 || isMuted(a.name)) {
                next = undefined
            } else if (a.votingPower >= fullThreshold) {
                if (prev !== "full") { fullNew.push(a.name); next = "full" }
            } else if (prev === undefined && warnMinutes > 0 && a.votingFullInHours * 60 <= warnMinutes) {
                soonNew.push(a.name); next = "soon"
            }
            if (next !== undefined) state[a.name] = next
            if (next !== prev) changed = true
        }
        // Keep entries for accounts missing from this snapshot (e.g. a failed lookup).
        for (var k in notified) if (!(k in state) && list.every(function(a) { return a.name !== k })) state[k] = notified[k]
        if (!changed) return
        notified = state
        stateFile.setText(JSON.stringify({ notified: state }, null, 2) + "\n")
        if (fullNew.length > 0)
            sendNotification("Voting power is full", names(fullNew) + (fullNew.length > 1 ? " are" : " is")
                + " at 100%. Go curate, mana is being wasted.")
        if (soonNew.length > 0)
            sendNotification("Voting power almost full", names(soonNew) + (soonNew.length > 1 ? " reach" : " reaches")
                + " 100% in under " + warnMinutes + " minutes.")
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try { root.notified = JSON.parse(text()).notified || {} } catch (e) { root.notified = ({}) }
            root.stateLoaded = true
            root.checkAlerts()
        }
        onLoadFailed: {
            root.notified = ({})
            root.stateLoaded = true
            root.checkAlerts()
        }
    }

    Timer {
        interval: root.rotateSeconds * 1000
        repeat: true
        running: root.rotation.length > 1
        onTriggered: root.rotIndex = (root.rotIndex + 1) % root.rotation.length
    }

    onRotationChanged: if (rotIndex >= rotation.length) rotIndex = 0

    function fmt(n) {
        return n >= 10000 ? Math.round(n / 1000) + "k" : (Math.round(n * 10) / 10).toString()
    }

    function normalize(name) {
        return String(name || "").trim().replace(/^@/, "").toLowerCase()
    }

    function validName(name) {
        return /^[a-z][a-z0-9-]{2,15}(\.[a-z][a-z0-9-]{2,15})*$/.test(name) && name.length <= 16
    }

    function saveAccounts() {
        accountsFile.setText(JSON.stringify({ accounts: root.accountNames, muted: root.mutedNames, settings: root.overrides }, null, 2) + "\n")
    }

    // Returns "" on success, otherwise a message for the panel to show.
    function addAccount(raw) {
        var name = normalize(raw)
        if (!validName(name)) return "\"" + raw + "\" is not a valid Hive username"
        if (accountNames.indexOf(name) >= 0) return "@" + name + " is already tracked"
        accountNames = accountNames.concat([name])
        saveAccounts()
        refresh()
        return ""
    }

    function removeAccount(name) {
        accountNames = accountNames.filter(function(n) { return n !== name })
        mutedNames = mutedNames.filter(function(n) { return n !== name })
        saveAccounts()
        if (accountNames.length === 0) { snapshot = null; error = ""; injectPanel() }
        else refresh()
    }

    // direction: -1 = up, +1 = down. Order is display-only, so no refetch.
    function moveAccount(name, direction) {
        var list = accountNames.slice()
        var i = list.indexOf(name), j = i + direction
        if (i < 0 || j < 0 || j >= list.length) return
        list.splice(i, 1)
        list.splice(j, 0, name)
        accountNames = list
        saveAccounts()
    }

    property int requestId: 0

    FileView {
        id: accountsFile
        path: root.accountsPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                var list = JSON.parse(text()).accounts
                root.accountNames = list instanceof Array ? list.map(root.normalize).filter(root.validName) : []
                var cfg = JSON.parse(text())
                root.mutedNames = cfg.muted instanceof Array ? cfg.muted : []
                root.overrides = cfg.settings && typeof cfg.settings === "object" ? cfg.settings : ({})
            } catch (e) {
                root.accountNames = []
            }
            root.accountsLoaded = true
            root.refresh()
        }
        onLoadFailed: {
            // No file yet: seed from shell.json (if given) and save it.
            var seed = root.accountsSetting instanceof Array ? root.accountsSetting : []
            root.accountNames = seed.map(root.normalize).filter(root.validName)
            root.accountsLoaded = true
            if (root.accountNames.length > 0) root.saveAccounts()
            root.refresh()
        }
    }

    onAccountNamesChanged: injectPanel()
    onLoadingChanged: injectPanel()
    onPrefsChanged: injectPanel()
    onMutedNamesChanged: injectPanel()

    function refresh() {
        if (!accountsLoaded) return
        if (accountNames.length === 0) { error = ""; return }
        var id = ++requestId
        loading = true
        Model.refreshData(accountNames, function(s) {
            if (id !== root.requestId) return // superseded by a newer refresh
            root.loading = false
            root.error = ""
            root.snapshot = s
            root.checkAlerts()
            root.injectPanel()
        }, function(msg) {
            if (id !== root.requestId) return
            root.loading = false
            root.error = msg
            console.warn("hive-portfolio:", msg)
        })
    }

    Timer {
        interval: root.refreshInterval * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function injectPanel() {
        var p = panelLoader.item
        if (!p) return
        p.host = root
        p.snapshot = root.snapshot
        p.accountNames = root.accountNames
        p.error = root.error
        p.loading = root.loading
        p.prefs = root.prefs
        p.mutedNames = root.mutedNames
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    Component.onCompleted: refresh()

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.vpText          // non-empty keeps the button visible; the label itself is drawn below
        labelVisible: false
        tooltipText: root.tooltip
        fixedWidth: Math.ceil(strip.implicitWidth + Style.spaceReal(horizontalMargin) * 2)
        onPressed: function(b) {
            if (b === Qt.MiddleButton) root.refresh()
            else root.togglePanel()
        }

        Row {
            id: strip
            anchors.centerIn: parent
            spacing: Style.space(6)

            // Hive logo; pulses when any tracked account has full voting power.
            Item {
                id: logoBox
                width: Style.space(16)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl("assets/hive-logo.png")
                    sourceSize.width: 64
                    sourceSize.height: 64
                    smooth: true
                    mipmap: true
                }
                PulseRing { active: root.anyFull && !root.currentFull; grow: 2 }
            }

            // Rotating avatar + its voting power.
            Row {
                id: slot
                spacing: Style.space(5)
                anchors.verticalCenter: parent.verticalCenter
                opacity: 1

                AccountAvatar {
                    name: root.current ? root.current.name : ""
                    size: Style.space(16)
                    hasRewards: root.currentRewards
                    alert: root.currentFull
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.vpText
                    color: root.currentFull ? "#ff6a3d" : button.foreground
                    font.family: button.fontFamily
                    font.pixelSize: button.fontSize
                    font.bold: root.currentFull
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Quick fade each time the rotation moves on.
                SequentialAnimation {
                    id: swap
                    NumberAnimation { target: slot; property: "opacity"; to: 0; duration: 120 }
                    PropertyAction { target: slot; property: "opacity"; value: 0 }
                    NumberAnimation { target: slot; property: "opacity"; to: 1; duration: 220 }
                }
            }
        }
    }

    onCurrentNameChanged: if (current) swap.restart()
}
