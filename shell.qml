import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// The shell switcher (SUPER + ALT + S): every rice theme with a Quickshell shell as a card (the shell it brings, its last look), pick one
// and it swaps to it without a flash. It runs on its own, apart from any shell, so it's still there while one
// shell goes and the next comes:
//   1. before it shows, a screenshot of the desktop as it is: the cover for the swap, and this theme's card
//   2. pick: the cover comes up (the screen looks unchanged), `rice <theme>` swaps everything under it
//   3. once the new shell is up, the cover fades away, and the switcher quits
// Esc (or a click outside the cards) closes it. `qs -c switcher` opens it; a second one does nothing.
ShellRoot {
    id: root

    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") + "/rice-switcher"
    readonly property string previews: Quickshell.env("HOME") + "/.cache/rice/previews"
    property var themes: []
    property string current: ""
    property int pick: 0
    property string stage: "shoot"              // shoot · pick · cover (swapping) · reveal (fading out)
    property string going: ""                   // the theme being switched to
    property string coverStamp: ""
    property var shots: []
    property string previewOfNow: ""             // the screenshot just taken (named for the theme that's on, a version or not)                       // the themes with a screenshot of their own (previews/<name>.png)

    // 1. the desktop as it is: full size for the cover, small for this theme's card
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$1" "$2" && grim "$1/cover.png" && cur=$(cat ~/.config/rice/current 2>/dev/null) && [ -n "$cur" ] && grim -s 0.4 "$2/$cur.png"; date +%s%N; echo "$cur"; ls "$2"', "sh", root.run, root.previews]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.coverStamp = lines[0];
                root.previewOfNow = lines[1] ?? "";
                root.shots = lines.slice(2);
                lister.running = true;
            }
        }
    }
    Process {
        id: lister
        command: ["sh", "-c", "~/.config/rice/rice list --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let all;
                try {
                    all = JSON.parse(text);
                } catch (e) {
                    Qt.quit();
                    return;
                }
                // the Quickshell ones (no waybar rices), and not a theme's other version (pure-dark is Pure's card)
                root.themes = all.filter(t => t.qs && !t.variant_of);
                const now = all.find(t => t.current);
                root.current = now ? (now.variant_of || now.name) : "";
                // on a version (pure-dark): its screenshot is the card's (Pure)
                if (now?.variant_of)
                    Quickshell.execDetached(["cp", root.previews + "/" + now.name + ".png", root.previews + "/" + now.variant_of + ".png"]);
                root.pick = Math.max(0, root.themes.findIndex(t => t.name === root.current));
                root.stage = "pick";
            }
        }
    }

    // 2. swap: the cover up, then rice under it
    function choose(i) {
        const t = themes[i];
        if (!t || stage !== "pick")
            return;
        if (t.name === current) {
            close();
            return;
        }
        going = t.name;
        stage = "cover";
        // (quiet: no "Rice switched" notification, the switch itself says so)
        // (back to the version of it used last: Mac Dark, if that's where you left it)
        swap.command = ["sh", "-c", '~/.config/rice/rice "$1" --quiet >/dev/null 2>&1', "sh", t.last || t.name];
        coverUp.restart();
    }
    Timer {
        id: coverUp                              // the cover's faded in over the cards: now swap
        interval: 220
        onTriggered: swap.running = true
    }
    Process {
        id: swap
        onExited: ready.start()
    }
    // 3. the new shell is up: a Quickshell one answers ipc; waybar (or none) just gets a moment
    property string shellOf: themes.find(t => t.name === going)?.qs ?? ""
    property int tries: 0
    Timer {
        id: ready
        interval: 150
        repeat: true
        function start() {
            root.tries = 0;
            restart();
        }
        onTriggered: {
            root.tries++;
            if (root.tries > 40) {               // 6 s: show it whatever state it's in
                stop();
                root.reveal();
                return;
            }
            if (!root.shellOf) {
                if (root.tries > 5) {
                    stop();
                    root.reveal();
                }
                return;
            }
            if (!probe.running)
                probe.running = true;
        }
    }
    Process {
        id: probe
        command: ["qs", "-c", root.shellOf, "ipc", "show"]
        stdout: StdioCollector {}
        onExited: code => {
            if (code === 0 && ready.running) {
                ready.stop();
                settle.restart();
            }
        }
    }
    Timer {
        id: settle                               // up, and its first frames drawn
        interval: 600
        onTriggered: root.reveal()
    }
    function reveal() {
        stage = "reveal";
        bye.restart();
    }
    Timer {
        id: bye
        interval: 750
        onTriggered: Qt.quit()
    }
    function close() {
        stage = "closing";
        bye.interval = 260;
        bye.restart();
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: root.stage !== "shoot"
        onVisibleChanged: if (visible)
            picker.forceActiveFocus()
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "rice-switcher"
        WlrLayershell.keyboardFocus: root.stage === "pick" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // the picker
        Item {
            id: picker
            anchors.fill: parent
            opacity: root.stage === "pick" ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
            focus: true
            Keys.onEscapePressed: root.close()
            Keys.onLeftPressed: root.pick = (root.pick + root.themes.length - 1) % root.themes.length
            Keys.onRightPressed: root.pick = (root.pick + 1) % root.themes.length
            Keys.onTabPressed: root.pick = (root.pick + 1) % root.themes.length
            Keys.onReturnPressed: root.choose(root.pick)

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.04, 0.04, 0.05, 0.82)
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: cards.top
                anchors.bottomMargin: 26
                text: "switch shell"
                color: "#f2f0ec"
                font.family: "Google Sans Flex"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Row {
                id: cards
                anchors.centerIn: parent
                spacing: 18
                // they rise in as it opens
                property real up: root.stage === "pick" ? 0 : 30
                anchors.verticalCenterOffset: up
                Behavior on up {
                    SpringAnimation {
                        spring: 3.5
                        damping: 0.32
                    }
                }
                Repeater {
                    model: root.themes
                    Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool on: index === root.pick
                        width: 280
                        height: 238
                        scale: on ? 1.04 : 1
                        Behavior on scale {
                            SpringAnimation {
                                spring: 4
                                damping: 0.35
                            }
                        }
                        RectangularShadow {
                            anchors.fill: face
                            radius: face.radius
                            blur: card.on ? 34 : 18
                            offset.y: card.on ? 10 : 5
                            color: Qt.rgba(0, 0, 0, card.on ? 0.5 : 0.32)
                        }
                        Rectangle {
                            id: face
                            anchors.fill: parent
                            radius: 22
                            color: "#1c1b1f"
                            border.width: card.on ? 2 : 1
                            border.color: card.on ? "#f2f0ec" : Qt.rgba(1, 1, 1, 0.08)
                            clip: true
                            // its look: the last screenshot of it, else its wallpaper
                            Image {
                                id: shot
                                x: 8
                                y: 8
                                width: parent.width - 16
                                height: 148
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(560, 296)
                                readonly property bool isNow: card.modelData.name === root.current
                                source: isNow || root.shots.includes(card.modelData.name + ".png") ? "file://" + root.previews + "/" + (isNow && root.previewOfNow ? root.previewOfNow : card.modelData.name) + ".png?" + (isNow ? root.coverStamp : "") : card.modelData.wallpaper ? "file://" + card.modelData.wallpaper : ""
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: shotMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1
                                }
                            }
                            Rectangle {
                                id: shotMask
                                anchors.fill: shot
                                radius: 15
                                visible: false
                                layer.enabled: true
                            }
                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: shot.bottom
                                anchors.margins: 14
                                anchors.topMargin: 10
                                spacing: 4
                                Row {
                                    spacing: 8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: card.modelData.title || card.modelData.name
                                        color: "#f2f0ec"
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 16
                                        font.weight: Font.DemiBold
                                    }
                                    Rectangle {          // the shell it brings
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: kind.implicitWidth + 14
                                        height: 20
                                        radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.1)
                                        Text {
                                            id: kind
                                            anchors.centerIn: parent
                                            text: card.modelData.qs || card.modelData.shell
                                            color: "#cfcac2"
                                            font.family: "Google Sans Flex"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                    }
                                    Rectangle {
                                        visible: card.modelData.name === root.current
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: nowText.implicitWidth + 14
                                        height: 20
                                        radius: 10
                                        color: "#f2f0ec"
                                        Text {
                                            id: nowText
                                            anchors.centerIn: parent
                                            text: "now"
                                            color: "#1c1b1f"
                                            font.family: "Google Sans Flex"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: card.modelData.about
                                    color: "#9b968e"
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.pick = card.index
                            onClicked: root.choose(card.index)
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: cards.bottom
                anchors.topMargin: 26
                text: "← → choose   ·   enter switch   ·   esc close"
                color: "#9b968e"
                font.family: "Google Sans Flex"
                font.pixelSize: 12
            }
        }

        // the cover: the desktop as it was, over the swap, then fading to show the new one
        Image {
            anchors.fill: parent
            source: root.coverStamp ? "file://" + root.run + "/cover.png?" + root.coverStamp : ""
            cache: false
            opacity: root.stage === "cover" ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: root.stage === "cover" ? 200 : 700
                    easing.type: Easing.InOutCubic
                }
            }
        }
    }
}
