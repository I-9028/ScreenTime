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

    switchWidth:  Kirigami.Units.gridUnit * 20
    switchHeight: Kirigami.Units.gridUnit * 26
    preferredRepresentation: compactRepresentation

    // ── Data ──
    property var appTimes: ({})
    property var tabTimes: ({})
    property real totalTime: 0
    property bool paused: false
    property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property var lastCheck: Date.now()
    property var expandedApps: ({})
    property var appList: []
    property int maxTabs: 10

    // ── Steam/Proton game resolution ──
    property string steamGameName: ""
    property real lastResolveTime: 0
    property string steamResolveCmd: ""

    // ── Helpers ──
    function fmt(s) {
        s = Math.floor(s)
        if (s < 60) {
            return s + "s"
        }
        var m = Math.floor(s / 60)
        if (m < 60) {
            return m + "m"
        }
        var h = Math.floor(m / 60)
        m = m % 60
        return h + "h " + (m < 10 ? "0" : "") + m + "m"
    }

    readonly property var browserIds: [
        "firefox", "chromium", "chrome", "brave", "vivaldi",
        "edge", "opera", "falkon", "librewolf", "zen",
        "floorp", "waterfox", "konqueror"
    ]

    function isBrowser(name) {
        var n = name.toLowerCase()
        for (var i = 0; i < browserIds.length; i++) {
            if (n.indexOf(browserIds[i]) >= 0) {
                return true
            }
        }
        return false
    }

    function getTab(title) {
        var seps = [" — ", " – ", " - "]
        for (var i = 0; i < seps.length; i++) {
            var p = title.lastIndexOf(seps[i])
            if (p > 0) {
                var tab = title.substring(0, p).trim()
                // Strip notification counts like "(52) WhatsApp" → "WhatsApp"
                tab = tab.replace(/^\(\d+\)\s*/, "")
                return tab
            }
        }
        return title
    }

    // BUG FIX: sort and assign were inside the for loop
    function rebuildList() {
        var arr = []
        for (var k in appTimes) {
            arr.push({ name: k, time: appTimes[k] })
        }
        arr.sort(function(a, b) { return b.time - a.time })
        appList = arr
    }

    // BUG FIX: return was inside the for loop — only ever returned 1 tab
    function tabList(appName) {
        var t = tabTimes[appName]
        if (!t) {
            return []
        }
        var arr = []
        for (var k in t) {
            arr.push({ title: k, time: t[k] })
        }
        arr.sort(function(a, b) { return b.time - a.time })
        return arr.slice(0, root.maxTabs)
    }

    function dayCheck() {
        var d = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (d !== today) {
            appTimes = {}
            tabTimes = {}
            totalTime = 0
            steamGameName = ""
            today = d
            rebuildList()
            persist()
        }
    }

    function resolveUnknown() {
        // LOGGING
        //console.log("ScreenTime resolveUnknown called")

        var now = Date.now()
        if (now - lastResolveTime < 5000) {
            console.log("ScreenTime resolveUnknown throttled")
            return
        }

        lastResolveTime = now

        steamResolveCmd =
        "sh -c \"ps -eo args 2>/dev/null"
        + " | grep -oiE 'steamapps/common/[^/]+'"
        + " | sed 's#steamapps/common/##'"
        + " | sort -u"
        + " | head -n 1\""

        console.log("ScreenTime running:", steamResolveCmd)
        runner.connectSource(steamResolveCmd)
    }
    //ps -eo args 2>/dev/null | grep -oP 'steamapps/common/\K[^/]+' | sort -u | head -1
    // ── Window tracking via TaskManager (already in Plasma) ──
    TaskManager.TasksModel {
        id: tasks
        sortMode:  TaskManager.TasksModel.SortDisabled
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    Timer {
        interval: 2000
        running: !root.paused
        repeat: true
        onTriggered: {
            root.dayCheck()
            var now = Date.now()
            var dt  = (now - root.lastCheck) / 1000
            root.lastCheck = now
            if (dt <= 0 || dt > 300) {
                return
            }

            for (var i = 0; i < tasks.count; i++) {
                var ix = tasks.index(i, 0)
                if (!tasks.data(ix, TaskManager.AbstractTasksModel.IsActive)) {
                    continue
                }

                // Get all available identifiers, safely convert to string
                var rawAppName = tasks.data(ix, TaskManager.AbstractTasksModel.AppName)
                var rawDisplay = tasks.data(ix, TaskManager.AbstractTasksModel.Display)
                var rawAppId   = tasks.data(ix, TaskManager.AbstractTasksModel.AppId)

                var appName = (rawAppName !== undefined && rawAppName !== null)
                              ? String(rawAppName).trim() : ""
                var ttl     = (rawDisplay !== undefined && rawDisplay !== null)
                              ? String(rawDisplay).trim() : ""
                var appId   = (rawAppId !== undefined && rawAppId !== null)
                              ? String(rawAppId).trim() : ""

                // Pick the best name: AppName > Display > cleaned AppId > Unknown
                var app = ""
                if (appName.length > 0) {
                    app = appName
                } else if (ttl.length > 0) {
                    app = ttl
                } else if (appId.length > 0) {
                    // Clean up AppId like "steam_app_730" → "Steam App 730"
                    app = appId.replace(/\.desktop$/i, "")
                               .replace(/[_-]/g, " ")
                               .replace(/\b\w/g, function(c) { return c.toUpperCase() })
                } else {
                    app = "Unknown"
                }

                // Steam/Proton games have no window properties —
                // use cached game name or kick off a process lookup
                if (app === "Unknown") {
                    if (root.steamGameName.length > 0) {
                        app = root.steamGameName
                    } else {
                        root.resolveUnknown()
                    }
                }

                // Debug: uncomment to see what TaskManager gives you
                // console.log("ScreenTime:", "AppName=" + appName,
                //             "Display=" + ttl, "AppId=" + appId, "→", app)

                var a = root.appTimes
                if (!a[app]) {
                    a[app] = 0
                }
                a[app] += dt
                root.appTimes = a
                root.totalTime += dt

                if (root.isBrowser(app) && ttl) {
                    var tab = root.getTab(ttl)
                    if (!root.tabTimes[app]) {
                        root.tabTimes[app] = {}
                    }
                    if (!root.tabTimes[app][tab]) {
                        root.tabTimes[app][tab] = 0
                    }
                    root.tabTimes[app][tab] += dt
                }

                root.appTimesChanged()
                root.totalTimeChanged()
                root.rebuildList()
                root.persist()
                break
            }
        }
    }

    // ── Persistence via plasma5support DataSource ──
    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(src, data) {
            var out = data["stdout"] ? data["stdout"].trim() : ""
            // LOGGING
            // console.log("ScreenTime runner:", src, "=>", out)
            // Handle Steam/Proton game name resolution
            if (src === root.steamResolveCmd) {
                if (out.length > 0) {
                    root.steamGameName = out
                    // Rename accumulated "Unknown" time to the real game name
                    if (root.appTimes["Unknown"]) {
                        var a = root.appTimes
                        if (!a[out]) {
                            a[out] = 0
                        }
                        a[out] += a["Unknown"]
                        delete a["Unknown"]
                        root.appTimes = a
                        root.appTimesChanged()
                        root.rebuildList()
                    }
                }
                disconnectSource(src)
                return
            }

            // Handle persistence load
            if (src.indexOf("cat ") === 0 && out.length > 0) {
                try {
                    var obj = JSON.parse(Qt.atob(out))
                    if (obj.date === root.today) {
                        root.appTimes  = obj.apps || {}
                        root.tabTimes  = obj.tabs || {}
                        root.totalTime = 0
                        for (var k in root.appTimes) {
                            root.totalTime += root.appTimes[k]
                        }
                        root.rebuildList()
                    }
                } catch (e) {
                    console.log("ScreenTime load error:", e)
                }
            }
            disconnectSource(src)
        }
    }

    function persist() {
        var payload = Qt.btoa(JSON.stringify({
            date: today, apps: appTimes, tabs: tabTimes
        }))
        runner.connectSource(
            "sh -c 'mkdir -p $HOME/.local/share/screentime && printf \"%s\" \""
            + payload
            + "\" > $HOME/.local/share/screentime/today.dat'"
        )
    }

    function load() {
        runner.connectSource("cat $HOME/.local/share/screentime/today.dat 2>/dev/null || true")
    }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.persist() }
    Component.onCompleted:   {
        console.log("ScreenTime MAIN QML LOADED")
        root.load()
    }
    Component.onDestruction: root.persist()

    // ══════════════════════════════════════════════════════════
    //  COMPACT — time in the panel (wraps to 2 lines if needed)
    // ══════════════════════════════════════════════════════════
    compactRepresentation: Item {
        Layout.minimumWidth: timeLabel.implicitWidth
        Layout.preferredWidth: timeLabel.implicitWidth
        Layout.minimumHeight: timeLabel.implicitHeight

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }

        PlasmaComponents.Label {
            id: timeLabel
            anchors.centerIn: parent
            text: root.fmt(root.totalTime)
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ══════════════════════════════════════════════════════════
    //  FULL — popup when you click the panel widget
    // ══════════════════════════════════════════════════════════
    fullRepresentation: ColumnLayout {
        Layout.preferredWidth:  Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        spacing: Kirigami.Units.smallSpacing

        // Header
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

        // App list
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

                        // App row
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
                                    if (!root.isBrowser(modelData.name)) {
                                        return
                                    }
                                    var map = root.expandedApps
                                    map[modelData.name] = !map[modelData.name]
                                    root.expandedApps = map
                                    root.expandedAppsChanged()
                                }
                            }

                            RowLayout {
                                id: appRowLayout
                                anchors {
                                    left: parent.left; right: parent.right
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

                        // Usage bar
                        Rectangle {
                            x: Kirigami.Units.smallSpacing * 2
                            height: 3
                            radius: 2
                            width: root.totalTime > 0
                                   ? Math.max(
                                       (parent.width - Kirigami.Units.smallSpacing * 4)
                                       * modelData.time / root.totalTime, 4)
                                   : 4
                            color: Kirigami.Theme.highlightColor
                        }

                        // Browser tabs (expanded)
                        Column {
                            visible: appDelegate.isExpanded
                            width: parent.width
                            leftPadding: Kirigami.Units.gridUnit * 2
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            spacing: 1

                            Repeater {
                                model: appDelegate.isExpanded
                                       ? root.tabList(modelData.name) : []

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

                // Empty state
                PlasmaComponents.Label {
                    visible: root.appList.length === 0
                    text: "No activity yet — start using some apps!"
                    opacity: 0.4
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: Kirigami.Units.gridUnit * 3
                }
            }
        }

        // Footer
        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing

            PlasmaComponents.ToolButton {
                icon.name: root.paused ? "media-playback-start" : "media-playback-pause"
                text: root.paused ? "Resume" : "Pause"
                onClicked: {
                    root.paused = !root.paused
                    if (!root.paused) {
                        root.lastCheck = Date.now()
                    }
                }
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.ToolButton {
                icon.name: "edit-clear-all"
                text: "Reset"
                onClicked: {
                    root.appTimes = {}
                    root.tabTimes = {}
                    root.totalTime = 0
                    root.steamGameName = ""
                    root.rebuildList()
                    root.persist()
                }
            }
        }
    }
}
