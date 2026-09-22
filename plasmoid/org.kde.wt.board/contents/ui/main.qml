/*
 * wt board — renders one JSON "card" from a command, themed by Plasma.
 *
 * The command prints:
 *   { "title": str, "subtitle": str, "badge": {"text": str, "level": lvl},
 *     "layout": "fields" | "list", "rows": [...] }
 *
 *   layout "fields": rows = [{label, text | spans:[{t,level}], level, url}]
 *   layout "list":   rows = [{state, level, age, name, title, note, url, tag,
 *                             session, exec, execIcon, execTip}]
 *
 *   lvl: ok | warn | error | info | dim | normal  — resolved to theme colors
 *   here, never hardcoded, so the widget follows the Plasma color scheme.
 *
 * Producers: `wt-status json <worktree>` and `wt-cloud json`.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: widget

    property var card: ({ title: "", subtitle: "", layout: "fields", rows: [] })
    property string err: ""

    readonly property string command: plasmoid.configuration.command || ""
    readonly property bool isList: card.layout === "list"

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground
    preferredRepresentation: fullRepresentation

    function levelColor(level) {
        switch (level) {
        case "ok":     return Kirigami.Theme.positiveTextColor
        case "warn":   return Kirigami.Theme.neutralTextColor
        case "error":  return Kirigami.Theme.negativeTextColor
        case "info":   return Kirigami.Theme.highlightColor
        case "dim":    return Kirigami.Theme.disabledTextColor
        default:       return Kirigami.Theme.textColor
        }
    }

    // spans -> StyledText, so one Label can hold several colors and still elide
    function spansHtml(row) {
        if (!row.spans) {
            var plain = row.text || ""
            if (row.url)
                return '<a href="' + row.url + '">' + plain + '</a>'
            return plain
        }
        var out = ""
        for (var i = 0; i < row.spans.length; i++) {
            var s = row.spans[i]
            var t = s.url ? '<a href="' + s.url + '">' + s.t + '</a>'
                          : '<font color="' + levelColor(s.level) + '">' + s.t + '</font>'
            out += (i ? " " : "") + (s.bold ? "<b>" + t + "</b>" : t)
        }
        return out
    }

    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            if (source !== widget.command)
                return                       // a row action, not the feed
            if (data["exit code"] !== 0) {
                widget.err = (data["stderr"] || "").split("\n")[0] || "command failed"
                return
            }
            try {
                widget.card = JSON.parse(data["stdout"])
                widget.err = ""
            } catch (e) {
                widget.err = "unreadable output"
            }
        }
        function run(cmd) {
            if (cmd)
                connectSource(cmd)
        }
    }

    Timer {
        interval: Math.max(1000, plasmoid.configuration.interval)
        running: widget.command !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: runner.run(widget.command)
    }

    fullRepresentation: Item {
        id: rep

        readonly property int pad: Kirigami.Units.largeSpacing

        implicitWidth: Math.max(header.implicitWidth, body.implicitWidth) + pad * 2
        implicitHeight: header.implicitHeight + body.implicitHeight
                        + Kirigami.Units.smallSpacing * 3 + pad * 2
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 4

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: rep.pad
            spacing: Kirigami.Units.smallSpacing

            // ---- header: identity left, verdict badge right ----
            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                ColumnLayout {
                    spacing: 0
                    Kirigami.Heading {
                        level: 4
                        text: widget.card.title || ""
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: widget.card.subtitle || ""
                        visible: text !== ""
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.disabledTextColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: badge
                    visible: !!widget.card.badge && !!widget.card.badge.text
                    radius: height / 2
                    color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.5)
                    implicitWidth: badgeLabel.implicitWidth + Kirigami.Units.largeSpacing
                    implicitHeight: badgeLabel.implicitHeight + Kirigami.Units.smallSpacing

                    readonly property color badgeColor: widget.levelColor(
                        widget.card.badge ? widget.card.badge.level : "normal")

                    PlasmaComponents.Label {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: widget.card.badge ? widget.card.badge.text : ""
                        color: badge.badgeColor
                    }
                }
            }

            PlasmaComponents.Label {
                visible: widget.err !== ""
                Layout.fillWidth: true
                text: widget.err
                color: Kirigami.Theme.negativeTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }

            // implicitWidth/Height of a Loader are read-only: it already takes
            // them from the loaded item, which is why both bodies are Items
            Loader {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: widget.isList ? listBody : fieldsBody
            }
        }
    }

    // ---- layout "fields": label column + value ----
    Component {
        id: fieldsBody

        // an Item wrapper, not a bare layout: a layout computes its own
        // implicit size and will not take an assignment
        Item {
            implicitWidth: Math.min(Kirigami.Units.gridUnit * 34,
                                    Math.max(Kirigami.Units.gridUnit * 20, fields.implicitWidth))
            implicitHeight: fields.implicitHeight

            ColumnLayout {
                id: fields
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Math.round(Kirigami.Units.smallSpacing / 2)

                Repeater {
                    model: widget.card.rows

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        PlasmaComponents.Label {
                            text: modelData.label || ""
                            color: Kirigami.Theme.disabledTextColor
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            Layout.alignment: Qt.AlignTop
                        }
                        PlasmaComponents.Label {
                            text: widget.spansHtml(modelData)
                            color: widget.levelColor(modelData.level)
                            textFormat: Text.StyledText
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            onLinkActivated: (link) => Qt.openUrlExternally(link)
                            HoverHandler {
                                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor
                                                                : Qt.ArrowCursor
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- layout "list": one hoverable row per session ----
    Component {
        id: listBody

        // A desktop applet is sized once, from the content it had when it was
        // created — and at creation the card is still empty. So ask for room for
        // a few rows regardless; the ScrollBar covers anything beyond.
        Item {
            implicitWidth: Kirigami.Units.gridUnit * 40
            implicitHeight: Math.max(Kirigami.Units.gridUnit * 15, list.contentHeight)

            ListView {
            id: list
            anchors.fill: parent
            model: widget.card.rows
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true

            QQC.ScrollBar.vertical: QQC.ScrollBar {
                id: vbar
                policy: list.contentHeight > list.height ? QQC.ScrollBar.AsNeeded
                                                         : QQC.ScrollBar.AlwaysOff
            }

            // two lines per session: identity on top, what it left off on
            // below — one line cannot hold a sentence and a branch name
            delegate: Item {
                id: row
                required property var modelData
                width: list.width
                height: Math.round(lines.implicitHeight + Kirigami.Units.smallSpacing * 2)

                HoverHandler { id: hover }
                TapHandler {
                    enabled: !!row.modelData.url
                    onTapped: Qt.openUrlExternally(row.modelData.url)
                }

                // the session id has no column to live in — 30 opaque chars per
                // row — but it is what you paste into `wt cloud branch`
                QQC.ToolTip.text: row.modelData.session || ""
                QQC.ToolTip.visible: hover.hovered && !execButton.hovered
                                     && QQC.ToolTip.text !== ""

                Rectangle {
                    anchors.fill: parent
                    radius: Kirigami.Units.smallSpacing
                    color: Kirigami.Theme.highlightColor
                    opacity: hover.hovered ? 0.15 : 0
                    Behavior on opacity { NumberAnimation { duration: 80 } }
                }

                ColumnLayout {
                    id: lines
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    // the ScrollBar floats over the row, so it lands on the
                    // action button unless the content gives way for it
                    // size < 1 means it has something to scroll: styles disagree
                    // on whether an idle AsNeeded bar is hidden or just empty
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                         + (vbar.visible && vbar.size < 1 ? vbar.width : 0)
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            implicitWidth: Kirigami.Units.gridUnit / 2
                            implicitHeight: implicitWidth
                            radius: implicitWidth / 2
                            color: widget.levelColor(row.modelData.level)
                        }
                        PlasmaComponents.Label {
                            text: row.modelData.state || ""
                            color: widget.levelColor(row.modelData.level)
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                        }
                        PlasmaComponents.Label {
                            text: row.modelData.name || ""
                            color: row.modelData.url ? Kirigami.Theme.linkColor
                                                     : Kirigami.Theme.textColor
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            visible: !!row.modelData.tag
                            radius: height / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Kirigami.Theme.disabledTextColor
                            implicitWidth: tagLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                            implicitHeight: tagLabel.implicitHeight + 2
                            PlasmaComponents.Label {
                                id: tagLabel
                                anchors.centerIn: parent
                                text: row.modelData.tag || ""
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.disabledTextColor
                            }
                        }
                        PlasmaComponents.Label {
                            text: row.modelData.age || ""
                            color: Kirigami.Theme.disabledTextColor
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.8
                        }
                        PlasmaComponents.ToolButton {
                            id: execButton
                            visible: !!row.modelData.exec
                            opacity: hover.hovered ? 1 : 0.25
                            icon.name: row.modelData.execIcon || "list-add"
                            display: QQC.AbstractButton.IconOnly
                            implicitHeight: Kirigami.Units.gridUnit * 1.4
                            implicitWidth: implicitHeight
                            QQC.ToolTip.text: row.modelData.execTip || ""
                            QQC.ToolTip.visible: hovered
                            onClicked: runner.run(row.modelData.exec)
                        }
                    }
                    PlasmaComponents.Label {
                        visible: text !== ""
                        // the session title first: the branch above is generated,
                        // this is the name a human gave it. Title before note so
                        // eliding eats the sentence, not the identity.
                        text: [row.modelData.title, row.modelData.note]
                              .filter(function (t) { return !!t }).join("  —  ")
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.gridUnit / 2
                                           + Kirigami.Units.smallSpacing
                    }
                }
            }
            }
        }
    }
}
