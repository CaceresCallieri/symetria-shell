import Quickshell
import Quickshell.Wayland

PanelWindow {
    required property string name

    WlrLayershell.namespace: `symmetria-${name}`
    color: "transparent"
}
