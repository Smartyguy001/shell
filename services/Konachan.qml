pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils

Singleton {
    id: root

    property bool busy: false
    property string destination
    property string fileName

    function setRandom(): void {
        if (busy)
            return;

        busy = true;

        const safeOnly = GlobalConfig.services.konachanSafeOnly;
        const tags = ["order:random"];
        if (safeOnly)
            tags.push("rating:safe");
        tags.push(...GlobalConfig.services.konachanTags.split(/\s+/).filter(tag => tag.length > 0));

        const host = safeOnly ? "https://konachan.net" : "https://konachan.com";
        const url = `${host}/post.json?limit=1&tags=${encodeURIComponent(tags.join(" "))}`;

        Requests.get(url, text => {
            let response;
            try {
                response = JSON.parse(text);
            } catch {
                root.showError(Tr.tr("Unable to parse Konachan response"));
                return;
            }

            if (!Array.isArray(response)) {
                root.showError(Tr.tr("Invalid response from Konachan"));
                return;
            }
            if (response.length === 0) {
                root.showError(Tr.tr("No posts matched"));
                return;
            }

            const post = response[0];
            if (!post || typeof post !== "object" || post.id === undefined || post.id === null || !post.file_url || !post.file_ext) {
                root.showError(Tr.tr("Konachan response did not contain a valid image"));
                return;
            }

            root.fileName = root.fileNameFor(post.file_url, post.id, post.file_ext);
            root.destination = `${Paths.wallsdir}/${root.fileName}`;
            downloadProcess.command = [
                "sh",
                "-c",
                '[ -f "$2" ] || { curl -fsSL --create-dirs -o "$2.part" "$1" && mv -f "$2.part" "$2"; } || { rm -f "$2.part"; exit 1; }',
                "--",
                post.file_url,
                root.destination
            ];
            downloadProcess.running = true;
        }, error => {
            root.showError(Tr.tr("Konachan request failed: %1").arg(error));
        }, {
            "User-Agent": "caelestia-shell"
        });
    }

    function utf8Length(codePoint: int): int {
        return codePoint <= 0x7F ? 1 : codePoint <= 0x7FF ? 2 : codePoint <= 0xFFFF ? 3 : 4;
    }

    function fileNameFor(url: string, id: var, ext: string): string {
        let segment = url.split(/[?#]/, 1)[0].split("/").pop() ?? "";
        try {
            segment = decodeURIComponent(segment);
        } catch {
            segment = segment.replace(/(?:%[0-9A-Fa-f]{2})+/g, sequence => {
                try {
                    return decodeURIComponent(sequence);
                } catch {
                    return sequence.replace(/%([0-9A-Fa-f]{2})/g, (match, hex) => String.fromCharCode(parseInt(hex, 16)));
                }
            });
        }

        const illegalCharacters = /[\\/:*?"<>|\u0000-\u001F]/g;
        const extension = String(ext ?? "").replace(/^\./, "").replace(illegalCharacters, "");
        const suffix = extension ? `.${extension}` : "";
        let name = segment.replace(illegalCharacters, "").replace(/\s+/g, " ").trim().replace(/[. ]+$/g, "");
        if (suffix && name.toLowerCase().endsWith(suffix.toLowerCase()))
            name = name.slice(0, -suffix.length);
        name = name.replace(/[. ]+$/g, "");

        let stem = name || `Konachan.com - ${id}`;
        let stemBytes = 0;
        for (const character of stem)
            stemBytes += root.utf8Length(character.codePointAt(0));
        let suffixBytes = 0;
        for (const character of suffix)
            suffixBytes += root.utf8Length(character.codePointAt(0));
        const maxStemBytes = Math.max(0, 255 - suffixBytes);
        if (stemBytes > maxStemBytes) {
            let shortened = "";
            let bytes = 0;
            for (const character of stem) {
                const characterBytes = root.utf8Length(character.codePointAt(0));
                if (bytes + characterBytes > maxStemBytes)
                    break;
                shortened += character;
                bytes += characterBytes;
            }
            stem = shortened.replace(/[. ]+$/g, "");
        }

        if (!stem)
            stem = `Konachan.com - ${id}`;
        return `${stem}${suffix}`;
    }

    function showError(reason: string): void {
        busy = false;
        Toaster.toast(Tr.tr("Konachan download failed"), reason, "error", Toast.Error);
    }

    IpcHandler {
        function random(): void {
            root.setRandom();
        }

        target: "konachan"
    }

    Process {
        id: downloadProcess

        stderr: StdioCollector {
            id: downloadStderr
        }

        onExited: exitCode => {
            root.busy = false;
            if (exitCode === 0) {
                Wallpapers.setWallpaper(root.destination);
                Toaster.toast(Tr.tr("Konachan wallpaper downloaded"), root.fileName, "cloud_download", Toast.Success);
            } else {
                const detail = downloadStderr.text.trim();
                root.showError(detail ? Tr.tr("Download failed: %1").arg(detail) : Tr.tr("Failed to download Konachan wallpaper"));
            }
        }
    }
}
