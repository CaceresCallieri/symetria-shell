import Quickshell.Io

JsonObject {
    property Ssh ssh: Ssh {}

    component Ssh: JsonObject {
        property bool enabled: true
        // Host must be configured in shell.json → screenshot.ssh.host
        property string host: ""
        property string remoteDir: "/tmp"
    }
}
