pragma Singleton

import QtQuick
import ScreenShareTest 1.0

QtObject {
    function env(name: string): string {
        return name === "XDG_RUNTIME_DIR" ? Bridge.runtimeDirectory : "";
    }
}
