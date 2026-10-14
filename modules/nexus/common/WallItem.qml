pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source
    property Flickable flickable
    property alias text: label.text
    property alias radius: imgWrapper.radius
    property alias imgHeight: imgWrapper.implicitHeight
    property bool fillLabel: true

    readonly property bool isVideo: Images.isVideoFile(root.source)
    readonly property string displayPath: Wallpapers.displayPathFor(root.source)
    readonly property bool inView: {
        if (!flickable)
            return true;

        const contentY = flickable.contentY;
        const viewportHeight = flickable.height;
        // mapToItem isn't reactive, so depend on the positions it uses
        void root.y;
        void root.parent?.y;
        const itemY = root.mapToItem(flickable.contentItem, 0, 0).y;
        const itemHeight = root.height;
        return itemY + itemHeight >= contentY - viewportHeight && itemY <= contentY + 2 * viewportHeight;
    }

    signal clicked

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.small

        StyledClippingRect {
            id: imgWrapper

            Layout.fillWidth: true
            implicitHeight: width
            radius: Tokens.rounding.largeIncreased
            color: Colours.tPalette.m3surfaceContainer

            Loader {
                anchors.centerIn: parent

                opacity: img.status === Image.Loading ? 1 : 0
                active: opacity > 0

                sourceComponent: StyledRect {
                    implicitWidth: loadingIndicator.implicitSize + Tokens.padding.large * 2
                    implicitHeight: loadingIndicator.implicitSize + Tokens.padding.large * 2

                    color: Colours.palette.m3primaryContainer
                    radius: Tokens.rounding.full

                    LoadingIndicator {
                        id: loadingIndicator

                        anchors.centerIn: parent
                        containsIcon: true
                        implicitSize: Math.min(imgWrapper.width, imgWrapper.height) * 0.3
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: root.isVideo ? "videocam" : "image"
                color: Colours.tPalette.m3outline
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.DemiBold).build()
            }

            CachingImage {
                id: img

                anchors.fill: parent
                path: root.inView && imgWrapper.width > 0 && imgWrapper.height > 0 ? root.displayPath : ""
                retainWhileLoading: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            StyledRect {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 4
                radius: Tokens.rounding.small
                color: "#CC000000"
                implicitWidth: badgeIcon.implicitWidth + 8
                implicitHeight: badgeIcon.implicitHeight + 4

                MaterialIcon {
                    id: badgeIcon

                    anchors.centerIn: parent
                    text: root.isVideo ? "videocam" : "image"
                    color: "white"
                    fontStyle: Tokens.font.icon.builders.small.scale(1).build()
                }
            }

            StyledRect {
                anchors.centerIn: parent
                visible: root.isVideo && img.status === Image.Error
                radius: Tokens.rounding.full
                color: Colours.palette.m3primaryContainer
                implicitWidth: fallbackIcon.implicitWidth + Tokens.padding.large * 2
                implicitHeight: fallbackIcon.implicitHeight + Tokens.padding.large * 2

                MaterialIcon {
                    id: fallbackIcon

                    anchors.centerIn: parent
                    text: "play_circle"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.5).build()
                }
            }
        }

        StyledText {
            id: label

            Layout.bottomMargin: Tokens.padding.small
            Layout.fillWidth: true
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    StateLayer {
        anchors.bottomMargin: root.fillLabel ? 0 : layout.implicitHeight - imgWrapper.implicitHeight
        onClicked: root.clicked()
    }
}
