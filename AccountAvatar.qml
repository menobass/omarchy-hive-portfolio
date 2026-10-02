import QtQuick
import QtQuick.Effects
import qs.Commons

// Round Hive avatar. A gold "$" badge marks unclaimed rewards; a pulsing ring
// marks full voting power.
Item {
    id: av
    property string name
    property int size: 16
    property bool hasRewards: false
    property bool alert: false
    property color alertColor: "#ff6a3d"
    property color rewardColor: "#e6b84a"

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
        Text {
            anchors.centerIn: parent
            text: av.name.length > 0 ? av.name[0].toUpperCase() : ""
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.6)
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Math.max(7, av.size * 0.5)
        }
    }
    Image {
        id: img
        anchors.fill: parent
        source: av.name !== "" ? "https://images.hive.blog/u/" + av.name + "/avatar/small" : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: av.size * 3
        sourceSize.height: av.size * 3
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: img
        visible: img.status === Image.Ready
        maskEnabled: true
        maskSource: mask
    }
    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: width / 2 }
    }

    PulseRing { active: av.alert; tone: av.alertColor; grow: Math.max(2, av.size * 0.12) }

    // "$" badge, bottom-right.
    Rectangle {
        visible: av.hasRewards
        readonly property real d: Math.max(9, av.size * 0.55)
        width: d
        height: d
        radius: d / 2
        x: av.width - d * 0.7
        y: av.height - d * 0.7
        color: av.rewardColor
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.55)
        Text {
            anchors.centerIn: parent
            text: "$"
            color: "#1b1b1b"
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: parent.d * 0.78
        }
    }
}
