pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Horizontal layout of project group pills.
///
/// One source feeds it: `SymmetriaThreads`, whose threads arrive from Mesura
/// Code's own socket. It used to union a second source — the `agent-bridge.py`
/// hub behind `AgentService`, which published Symmetria IDE's agents — and the
/// two were kept apart all the way up to this file precisely so that the day
/// the IDE was retired, one branch could be deleted and the other left
/// untouched. That day arrived; this is what the deletion left.
///
/// `AgentService` still exists, but only as dictation plumbing: it resolves an
/// agent's Neovim socket for `SttJob`. Nothing in the bar reads it any more and
/// nothing here should start to — issue #64 tracks the rest of its retirement.
Item {
    id: root

    implicitHeight: Config.agentbar.sizes.innerHeight
    implicitWidth: layout.implicitWidth

    RowLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        Repeater {
            // Keyed on the project NAME — the only identifier the rows carry,
            // since Mesura names a project by its own project title and the pill
            // prints that name. A ScriptModel rather than a plain array for the
            // reason `docs/qml-pitfalls.md` records under "Repeater over a
            // freshly-rebuilt JS array resets ALL delegates every update", and
            // which `ProjectGroup`'s own chip Repeater already answers the same
            // way. Mesura emits a delta per thread update, so a plain array
            // would tear down every pill in the bar whenever one unrelated
            // thread moved.
            model: ScriptModel {
                values: SymmetriaThreads.projectGroups
                objectProp: "project"
            }

            ProjectGroup {
                required property var modelData

                project: modelData.project
                agents: modelData.agents
            }
        }
    }
}
