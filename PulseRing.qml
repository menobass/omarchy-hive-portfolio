import QtQuick

// Soft pulsing ring drawn just outside its parent. Used to flag accounts whose
// voting power is full (mana is being wasted).
Rectangle {
    id: ring
    property bool active: false
    property color tone: "#ff6a3d"
    property real grow: 3          // px the ring sits outside the parent

    anchors.centerIn: parent
    width: parent.width + grow * 2
    height: parent.height + grow * 2
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: tone
    visible: active
    opacity: 0

    SequentialAnimation on opacity {
        running: ring.active
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.15; duration: 650; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on scale {
        running: ring.active
        loops: Animation.Infinite
        NumberAnimation { to: 1.12; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
    }
}
