pragma ComponentBehavior: Bound

import QtQuick

// This model has no Quickshell dependency so Qt Quick tests can exercise the
// same navigation and region geometry that the native layer uses.
QtObject {
    id: root

    property var context: ({}) // intentional var: portal JSON context
    property int modeIndex: 0
    property int currentIndex: 0
    property int outputIndex: 0
    property string query: ""
    property bool remember: false
    property var region: null // intentional var: normalized rectangle or null
    readonly property var modes: ["windows", "screens", "workspaces", "region"] // intentional var: stable mode names
    readonly property string mode: modes[modeIndex]
    readonly property var outputs: context.outputs ?? [] // intentional var: portal output objects
    readonly property var output: outputs[outputIndex] ?? null // intentional var: selected portal output
    readonly property var items: (context.sources?.[mode] ?? []).filter(source => `${source.title} ${source.app} ${source.detail}`.toLocaleLowerCase().includes(query.toLocaleLowerCase())) // intentional var: filtered source objects
    readonly property var current: items[currentIndex] ?? null // intentional var: selected source
    readonly property bool canConfirm: mode === "region" ? output !== null && region !== null : current !== null
    readonly property var regionPixelRect: regionPixels() // intentional var: rounded output-local rectangle or null
    readonly property string regionSize: regionPixelRect ? `${regionPixelRect.width} × ${regionPixelRect.height} px` : "Arrastrá para marcar el área que querés compartir."

    function regionPixels(): var {
        if (!output || !region)
            return null;
        // Match the adapter: rounding the origin can reduce the remaining pixels.
        const x = Math.floor(region.x * output.width + 0.5);
        const y = Math.floor(region.y * output.height + 0.5);
        return {
            x,
            y,
            width: Math.min(output.width - x, Math.floor(region.width * output.width + 0.5)),
            height: Math.min(output.height - y, Math.floor(region.height * output.height + 0.5))
        };
    }

    function load(value: var): void {
        context = value;
        modeIndex = 0;
        currentIndex = 0;
        outputIndex = Math.max(0, outputs.findIndex(item => item.name === value.preferredOutput));
        query = "";
        region = null;
        remember = value.rememberDefault === true;
    }

    function setMode(index: int): void {
        modeIndex = (index + modes.length) % modes.length;
        currentIndex = 0;
        query = "";
    }

    function setQuery(value: string): void {
        query = value;
        currentIndex = 0;
    }

    function selectOutput(index: int): void {
        outputIndex = index;
        region = null;
    }

    function move(dx: int, dy: int, columns: int, resize: bool): void {
        if (mode === "region") {
            if (!output)
                return;
            const previous = region ?? {
                x: 0.2,
                y: 0.2,
                width: 0.6,
                height: 0.6
            };
            let x = previous.x, y = previous.y, width = previous.width, height = previous.height;
            if (resize) {
                width = Math.max(1 / output.width, Math.min(1 - x, width + dx * 0.01));
                height = Math.max(1 / output.height, Math.min(1 - y, height + dy * 0.01));
            } else {
                x = Math.max(0, Math.min(1 - width, x + dx * 0.01));
                y = Math.max(0, Math.min(1 - height, y + dy * 0.01));
            }
            region = {
                x,
                y,
                width,
                height
            };
            return;
        }
        const columnCount = Math.max(1, columns);
        const rowStart = Math.floor(currentIndex / columnCount) * columnCount;
        if (dy)
            currentIndex = Math.max(0, Math.min(items.length - 1, currentIndex + dy * columnCount));
        else
            currentIndex = Math.max(rowStart, Math.min(Math.min(items.length, rowStart + columnCount) - 1, currentIndex + dx));
        currentIndex = Math.max(0, currentIndex);
    }

    function dragRegion(startX: real, startY: real, endX: real, endY: real): void {
        const x = Math.max(0, Math.min(1, Math.min(startX, endX)));
        const y = Math.max(0, Math.min(1, Math.min(startY, endY)));
        const width = Math.max(0, Math.min(1, Math.max(startX, endX)) - x);
        const height = Math.max(0, Math.min(1, Math.max(startY, endY)) - y);
        region = output && width * output.width >= 1 && height * output.height >= 1 ? {
            x,
            y,
            width,
            height
        } : null;
    }

    function selection(): var {
        return {
            mode,
            id: current?.id ?? "",
            output: output?.name ?? "",
            region,
            remember
        };
    }
}
