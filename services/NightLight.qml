pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

Singleton {
    id: root

    property alias enabled: props.enabled
    readonly property int temperature: Math.max(1000, Math.min(6500, GlobalConfig.utilities.nightLight.temperature))

    function apply(): void {
        proc.running = false;
        proc.command = ["sh", "-c", "hyprctl hyprsunset temperature " + temperature + " >/dev/null 2>&1 || { hyprsunset -t " + temperature + " >/dev/null 2>&1 & }"];
        proc.running = true;
    }

    function reset(): void {
        proc.running = false;
        proc.command = ["sh", "-c", "hyprctl hyprsunset identity >/dev/null 2>&1"];
        proc.running = true;
    }

    onEnabledChanged: {
        if (enabled) {
            apply();
            if (GlobalConfig.utilities.toasts.nightLightChanged)
                Toaster.toast(Tr.tr("Night light enabled"), Tr.tr("Colour temperature set to %1K").arg(temperature), "nights_stay");
        } else {
            reset();
            if (GlobalConfig.utilities.toasts.nightLightChanged)
                Toaster.toast(Tr.tr("Night light disabled"), Tr.tr("Colour temperature restored"), "nights_stay");
        }
    }

    onTemperatureChanged: if (enabled) apply()

    Component.onCompleted: if (enabled) apply()

    PersistentProperties {
        id: props

        property bool enabled: false

        reloadableId: "nightLight"
    }

    Process {
        id: proc
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        function setTemperature(temp: int): void {
            GlobalConfig.utilities.nightLight.temperature = temp;
        }

        function getTemperature(): int {
            return temperature;
        }

        target: "nightLight"
    }
}
