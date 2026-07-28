import QtQuick
import QtQuick.Controls as QQC
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_command: commandField.text
    property alias cfg_interval: intervalBox.value
    property alias cfg_maxRows: maxRowsBox.value

    QQC.TextField {
        id: commandField
        Kirigami.FormData.label: i18n("Command:")
        placeholderText: "wt-cloud json"
    }

    QQC.SpinBox {
        id: intervalBox
        Kirigami.FormData.label: i18n("Refresh (ms):")
        from: 1000
        to: 600000
        stepSize: 1000
    }

    QQC.SpinBox {
        id: maxRowsBox
        Kirigami.FormData.label: i18n("Rows before scrolling:")
        from: 0
        to: 100
    }

    QQC.Label {
        Kirigami.FormData.label: ""
        text: i18n("The command must print one JSON card:\ntitle, subtitle, badge, layout (fields|list), rows.")
        opacity: 0.7
        wrapMode: Text.WordWrap
    }
}
