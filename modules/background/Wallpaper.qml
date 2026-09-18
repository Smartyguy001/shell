pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen

    property string source: Wallpapers.current
    property Item current
    property bool completed
    readonly property bool isPaused: {
        const fullscreen = Hypr.monitorFor(screen)?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        return (Config.background.video.pauseOnFullscreen && fullscreen) || (Config.background.video.pauseInGameMode && GameMode.enabled);
    }

    function switchSource(): void {
        if (!source) {
            current = null;
            return;
        }

        let component = imgComp;
        let path = source;
        if (Images.isVideoFile(source)) {
            if (isPaused)
                path = Wallpapers.displayPathFor(source);
            else
                component = videoComp;
        } else if (Images.isGifFile(source)) {
            component = gifComp;
        }
        current = component.createObject(root, {
            wallpaperPath: path
        });
    }

    onSourceChanged: switchSource()
    onIsPausedChanged: {
        if (Images.isVideoFile(source))
            switchSource();
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                switchSource();
                completed = true;
            });
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: Tr.tr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: Tr.tr("Select a wallpaper")
                            filterLabel: Tr.tr("Image and video files")
                            filters: [...Images.validImageExtensions, ...Images.validVideoExtensions]
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: Tr.tr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imgComp

        CachingImage {
            id: img

            property string wallpaperPath
            property bool ready

            anchors.fill: parent
            path: Wallpapers.displayPathFor(img.wallpaperPath)
            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready) {
                    ready = true;
                    anim.start();
                }
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== img && (root.current?.ready ?? true) // qmllint disable missing-property
                interval: anim.duration
                onTriggered: img.destroy()
            }
        }
    }

    Component {
        id: gifComp

        AnimatedImage {
            id: gif

            property string wallpaperPath
            property bool ready

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: `file://${wallpaperPath}`
            playing: true
            opacity: 0

            onStatusChanged: {
                if (status === AnimatedImage.Ready) {
                    ready = true;
                    anim.start();
                }
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== gif && (root.current?.ready ?? true) // qmllint disable missing-property
                interval: anim.duration
                onTriggered: gif.destroy()
            }
        }
    }

    Component {
        id: videoComp

        Item {
            id: videoContainer

            property string wallpaperPath
            property bool ready

            anchors.fill: root
            opacity: 0

            MediaPlayer {
                id: player

                source: videoContainer.wallpaperPath ? `file://${videoContainer.wallpaperPath}` : ""
                videoOutput: output
                loops: MediaPlayer.Infinite
                autoPlay: true

                audioOutput: AudioOutput {
                    muted: Config.background.video.muted
                }

                onPlaybackStateChanged: function (playbackState) {
                    if (playbackState === MediaPlayer.PlayingState) {
                        videoContainer.ready = true;
                        videoAnim.start();
                    }
                }

                onErrorOccurred: function (error, errorString) {
                    console.warn("Video wallpaper error:", errorString);
                }
            }

            VideoOutput {
                id: output

                anchors.fill: videoContainer
                fillMode: VideoOutput.PreserveAspectCrop
            }

            Anim on opacity {
                id: videoAnim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== videoContainer && (root.current?.ready ?? true) // qmllint disable missing-property
                interval: videoAnim.duration
                onTriggered: videoContainer.destroy()
            }
        }
    }
}
