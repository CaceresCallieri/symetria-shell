import Quickshell.Io

JsonObject {
    property Ssh ssh: Ssh {}

    component Ssh: JsonObject {
        property bool enabled: true
        property string host: "corpy"
        property string remoteDir: "/tmp"
    }
}
