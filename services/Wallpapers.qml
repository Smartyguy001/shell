pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear
    property int thumbVersion

    function videoThumbPath(path: string): string {
        const separator = path.lastIndexOf("/");
        const dir = path.substring(0, separator);
        const name = path.substring(separator + 1);
        const extension = name.lastIndexOf(".");
        const stem = extension > 0 ? name.substring(0, extension) : name;
        return `${dir}/.thumbs/${stem}.jpg`;
    }

    function displayPathFor(path: string): string {
        if (!Images.isVideoFile(path))
            return path;
        return `${videoThumbPath(path)}?v=${thumbVersion}`;
    }

    function getCategoryFor(w: FileSystemEntry): string {
        const isVideo = w.parentDir === Paths.videowallsdir || w.parentDir.startsWith(`${Paths.videowallsdir}/`);
        const base = isVideo ? Paths.videowallsdir : Paths.wallsdir;
        let category = w.parentDir.slice(base.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        if (!Images.isVideoFile(path)) {
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
            return;
        }

        setVideoProc.command = [
            "sh",
            "-c",
            'f="$1"; v="$2"; p="$3"; t="${f%/*}"; mkdir -p "$t"; if [ ! -f "$f" ]; then if command -v ffmpegthumbnailer >/dev/null 2>&1; then ffmpegthumbnailer -i "$v" -o "$f" -s 512 -q 8; else ffmpeg -y -loglevel error -ss 1 -i "$v" -frames:v 1 -vf "scale=512:-2" "$f"; fi; fi; caelestia wallpaper -f "$f" "${@:4}" && printf %s "$v" > "$p"',
            "--",
            videoThumbPath(path),
            path,
            currentNamePath,
            ...smartArg
        ];
        setVideoProc.running = true;
    }

    function preview(path: string): void {
        previewPath = Images.isVideoFile(path) ? videoThumbPath(path) : path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function updateThumbs(): void {
        thumbTimer.restart();
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: [...wallpapers.entries, ...videoWallpapers.entries]
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            const transientThumb = Images.isVideoFile(root.actualCurrent) && wall === root.videoThumbPath(root.actualCurrent);
            if (!transientThumb)
                root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    FileSystemModel {
        id: videoWallpapers

        recursive: true
        path: Paths.videowallsdir
        nameFilters: Images.validVideoExtensions.map(extension => `*.${extension}`)
        filter: FileSystemModel.Files

        onEntriesChanged: thumbTimer.restart()
    }

    Timer {
        id: thumbTimer

        interval: 500
        onTriggered: {
            if (!thumbProc.running && videoWallpapers.entries.length > 0)
                thumbProc.running = true;
        }
    }

    Process {
        id: thumbProc

        command: [
            "sh",
            "-c",
            'for f in "$@"; do d="${f%/*}/.thumbs"; n="${f##*/}"; n="${n%.*}"; t="$d/$n.jpg"; [ -f "$t" ] && continue; mkdir -p "$d"; if command -v ffmpegthumbnailer >/dev/null 2>&1; then ffmpegthumbnailer -i "$f" -o "$t" -s 512 -q 8; else ffmpeg -y -loglevel error -ss 1 -i "$f" -frames:v 1 -vf "scale=512:-2" "$t"; fi; done',
            "--",
            ...videoWallpapers.entries.map(entry => entry.path)
        ]
        onExited: thumbVersion++
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                if (root.showPreview)
                    Colours.showPreview = true;
            }
        }
    }

    Process {
        id: setVideoProc

        running: false
    }
}
