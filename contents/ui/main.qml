import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    switchWidth: Kirigami.Units.gridUnit * 20
    switchHeight: Kirigami.Units.gridUnit * 26
    preferredRepresentation: compactRepresentation

    property var appTimes: ({})
    property var tabTimes: ({})
    property var expandedApps: ({})
    property var appList: []
    property real totalTime: 0
    property real lastCheck: Date.now()
    property bool paused: false
    property bool dirty: false
    property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property int maxTabs: 10

    // Steam/Proton windows report no app name, so the game is looked up via ps
    property string steamGameName: ""
    property real lastResolveTime: 0

    readonly property string dataDir: "$HOME/.local/share/screentime"
    readonly property string dataFile: dataDir + "/today.dat"
    readonly property string loadCmd: "cat \"" + dataFile + "\" 2>/dev/null || true"
    // Steam's own launcher process; its args carry the real game path
    readonly property string steamResolveCmd:
        "ps -eo args | grep -E '^[^ ]*/[r]eaper SteamLaunch' | head -n 1"

    readonly property var browserPattern:
        /\b(firefox|chromium|chrome|brave|vivaldi|edge|opera|falkon|librewolf|zen|floorp|waterfox|konqueror)\b/i

    function fmt(seconds) {
        var s = Math.floor(seconds)
        if (s < 60) return s + "s"
        var m = Math.floor(s / 60)
        if (m < 60) return m + "m"
        var h = Math.floor(m / 60)
        m = m % 60
        return h + "h " + (m < 10 ? "0" : "") + m + "m"
    }

    function isBrowser(name) {
        return browserPattern.test(name)
    }

    // "(3) Inbox - Mail - Mozilla Firefox" -> "Inbox - Mail"
    function getTab(title) {
        var seps = [" — ", " – ", " - "]
        var cut = -1
        for (var i = 0; i < seps.length; i++) {
            cut = Math.max(cut, title.lastIndexOf(seps[i]))
        }
        var tab = cut > 0 ? title.substring(0, cut).trim() : title
        return tab.replace(/^\(\d+\)\s*/, "")
    }

    function rebuildList() {
        var arr = []
        for (var k in appTimes) {
            arr.push({ name: k, time: appTimes[k] })
        }
        arr.sort(function(a, b) { return b.time - a.time })
        appList = arr
    }

    function tabList(appName) {
        var tabs = tabTimes[appName]
        if (!tabs) return []
        var arr = []
        for (var k in tabs) {
            arr.push({ title: k, time: tabs[k] })
        }
        arr.sort(function(a, b) { return b.time - a.time })
        return arr.slice(0, maxTabs)
    }

    // The saved state is passed to the shell as a single argument, which Linux
    // caps at 128 KiB, so the tab table can't be allowed to grow forever.
    function pruneTabs(tabs) {
        var keys = Object.keys(tabs)
        if (keys.length <= 100) return
        keys.sort(function(a, b) { return tabs[b] - tabs[a] })
        for (var i = 50; i < keys.length; i++) {
            delete tabs[keys[i]]
        }
    }

    function resetData() {
        appTimes = {}
        tabTimes = {}
        totalTime = 0
        steamGameName = ""
        rebuildList()
        persist()
    }

    function dayCheck() {
        var d = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (d !== today) {
            today = d
            resetData()
        }
    }

    function resolveUnknown() {
        var now = Date.now()
        if (now - lastResolveTime < 10000) return
        lastResolveTime = now
        runner.connectSource(steamResolveCmd)
    }

    // Library games live under steamapps/common/<dir>. Non-Steam shortcuts
    // don't, so fall back to the folder holding the .exe that Proton launches.
    function steamNameFromLine(line) {
        var re = /steamapps\/common\/([^\/]+)/gi
        var m
        while ((m = re.exec(line)) !== null) {
            if (!/^(proton|steam linux runtime|steamlinuxruntime|steamworks)/i.test(m[1])) return m[1]
        }
        var exe = line.match(/ waitforexitandrun (\/.+?\.exe)/i)
        if (exe) {
            var parts = exe[1].split("/")
            parts.pop()
            return parts.pop()
        }
        return ""
    }

    // An empty result means no game is running any more
    function applySteamName(name) {
        steamGameName = name
        if (!name || !appTimes["Unknown"]) return
        appTimes[name] = (appTimes[name] || 0) + appTimes["Unknown"]
        delete appTimes["Unknown"]
        appTimesChanged()
        rebuildList()
        dirty = true
    }

    function applySaved(encoded) {
        try {
            var saved = JSON.parse(Qt.atob(encoded))
            if (saved.date !== today) return
            appTimes = saved.apps || {}
            tabTimes = saved.tabs || {}
            var sum = 0
            for (var k in appTimes) sum += appTimes[k]
            totalTime = sum
            rebuildList()
        } catch (e) {
            console.warn("ScreenTime: failed to load data:", e)
        }
    }

    function addTime(app, title, dt) {
        appTimes[app] = (appTimes[app] || 0) + dt
        totalTime += dt

        if (isBrowser(app) && title) {
            var tabs = tabTimes[app] || (tabTimes[app] = {})
            var tab = getTab(title)
            tabs[tab] = (tabs[tab] || 0) + dt
            pruneTabs(tabs)
        }

        appTimesChanged()
        tabTimesChanged()
        rebuildList()
        dirty = true
    }

    function tick() {
        dayCheck()

        var now = Date.now()
        var dt = (now - lastCheck) / 1000
        lastCheck = now
        if (dt <= 0 || dt > 300) return

        for (var i = 0; i < tasks.count; i++) {
            var ix = tasks.index(i, 0)
            if (!tasks.data(ix, TaskManager.AbstractTasksModel.IsActive)) continue

            var appName = String(tasks.data(ix, TaskManager.AbstractTasksModel.AppName) || "").trim()
            var display = String(tasks.data(ix, TaskManager.AbstractTasksModel.Display) || "").trim()
            var appId   = String(tasks.data(ix, TaskManager.AbstractTasksModel.AppId) || "").trim()

            var app = appName.length > 0 ? appName :
                      display.length > 0 ? display :
                      appId.length > 0 ? appId.replace(/\.desktop$/i, "").replace(/[_-]/g, " ").replace(/\b\w/g, function(c) { return c.toUpperCase() }) :
                      "Unknown"

            if (app === "Unknown") {
                resolveUnknown()
                if (steamGameName.length > 0) app = steamGameName
            }

            addTime(app, display, dt)
            break
        }
    }

    function persist() {
        var payload = Qt.btoa(JSON.stringify({ date: today, apps: appTimes, tabs: tabTimes }))
        // base64 is safe inside single quotes
        runner.connectSource("mkdir -p \"" + dataDir + "\" && printf %s '"
                             + payload + "' > \"" + dataFile + "\"")
        dirty = false
    }

    TaskManager.TasksModel {
        id: tasks
        sortMode: TaskManager.TasksModel.SortDisabled
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    Timer {
        interval: 2000
        running: !root.paused
        repeat: true
        onTriggered: root.tick()
    }

    // Saves are batched here rather than spawning a shell on every tick
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (root.dirty) root.persist()
        }
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []

        onNewData: function(src, data) {
            disconnectSource(src)
            var out = data.stdout ? data.stdout.trim() : ""

            if (src === root.steamResolveCmd) {
                root.applySteamName(root.steamNameFromLine(out))
            } else if (src === root.loadCmd && out.length > 0) {
                root.applySaved(out)
            }
        }
    }

    Component.onCompleted: runner.connectSource(loadCmd)
    Component.onDestruction: {
        if (dirty) persist()
    }

    compactRepresentation: Item {
        Layout.minimumWidth: timeLabel.implicitWidth
        Layout.preferredWidth: timeLabel.implicitWidth
        Layout.minimumHeight: timeLabel.implicitHeight

        MouseArea { anchors.fill: parent; onClicked: root.expanded = !root.expanded }

        PlasmaComponents.Label {
            id: timeLabel
            anchors.centerIn: parent
            width: parent.width
            text: root.fmt(root.totalTime)
            font.bold: true
            wrapMode: Text.NoWrap
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            horizontalAlignment: Text.AlignHCenter
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: "Screen Time"
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: root.fmt(root.totalTime)
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.35
                color: Kirigami.Theme.highlightColor
            }
        }

        PlasmaComponents.Label {
            text: Qt.formatDate(new Date(), "dddd, MMMM d")
            opacity: 0.5
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
            Layout.leftMargin: Kirigami.Units.smallSpacing
        }

        Kirigami.Separator { Layout.fillWidth: true }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: appCol.height
            clip: true
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            Column {
                id: appCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.appList

                    delegate: Column {
                        id: appDelegate
                        width: appCol.width
                        property bool isExpanded: root.expandedApps[modelData.name] === true

                        Rectangle {
                            width: parent.width
                            height: appRowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: Kirigami.Units.smallSpacing
                            color: rowMouse.containsMouse
                                   ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                             Kirigami.Theme.highlightColor.g,
                                             Kirigami.Theme.highlightColor.b, 0.08)
                                   : "transparent"

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.isBrowser(modelData.name)
                                             ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (!root.isBrowser(modelData.name)) return
                                    var map = Object.assign({}, root.expandedApps)
                                    map[modelData.name] = !map[modelData.name]
                                    root.expandedApps = map
                                }
                            }

                            RowLayout {
                                id: appRowLayout
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    margins: Kirigami.Units.smallSpacing * 2
                                    verticalCenter: parent.verticalCenter
                                }

                                PlasmaComponents.Label {
                                    text: modelData.name
                                    font.weight: Font.DemiBold
                                }
                                PlasmaComponents.Label {
                                    visible: root.isBrowser(modelData.name)
                                    text: appDelegate.isExpanded ? "▾" : "▸"
                                    opacity: 0.4
                                }
                                Item { Layout.fillWidth: true }
                                PlasmaComponents.Label {
                                    text: {
                                        var pct = root.totalTime > 0
                                                  ? Math.round(modelData.time / root.totalTime * 100) : 0
                                        return root.fmt(modelData.time) + "   " + pct + "%"
                                    }
                                    opacity: 0.75
                                }
                            }
                        }

                        Rectangle {
                            x: Kirigami.Units.smallSpacing * 2
                            height: 3
                            radius: 2
                            width: root.totalTime > 0
                                   ? Math.max((parent.width - Kirigami.Units.smallSpacing * 4)
                                              * modelData.time / root.totalTime, 4)
                                   : 4
                            color: Kirigami.Theme.highlightColor
                        }

                        Column {
                            visible: appDelegate.isExpanded
                            width: parent.width
                            leftPadding: Kirigami.Units.gridUnit * 2
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            spacing: 1

                            Repeater {
                                model: appDelegate.isExpanded ? root.tabList(modelData.name) : []

                                delegate: RowLayout {
                                    width: parent.width - Kirigami.Units.gridUnit * 2.5
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        text: modelData.title
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                                        opacity: 0.6
                                    }
                                    PlasmaComponents.Label {
                                        text: root.fmt(modelData.time)
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                                        opacity: 0.4
                                    }
                                }
                            }
                        }
                    }
                }

                PlasmaComponents.Label {
                    visible: root.appList.length === 0
                    text: "No activity yet"
                    opacity: 0.4
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: Kirigami.Units.gridUnit * 3
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing

            PlasmaComponents.ToolButton {
                icon.name: root.paused ? "media-playback-start" : "media-playback-pause"
                text: root.paused ? "Resume" : "Pause"
                onClicked: {
                    root.paused = !root.paused
                    if (!root.paused) root.lastCheck = Date.now()
                }
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.ToolButton {
                icon.name: "edit-clear-all"
                text: "Reset"
                onClicked: root.resetData()
            }
        }
    }
}
