pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Horizontal layout of project group pills.
///
/// Two independent sources feed it: `AgentService`, whose agents arrive from
/// the `agent-bridge.py` hub, and `SymmetriaThreads`, whose threads arrive
/// from Mesura Code's own socket. They are UNIONED here rather than merged
/// upstream, and that is the whole seam.
///
/// The reason is a decision about the future rather than about the code:
/// Symmetria IDE and its hub are deliberately temporary. When they go, one
/// branch below is deleted and the other is untouched — which would not be
/// true if Mesura's rows were projected into `AgentService.agents` on their
/// way here.
///
/// A project worked in BOTH surfaces lands in one pill with both sets of
/// chips, and that falls out of grouping by name rather than needing code of
/// its own. It is a transitional convenience, not a goal.
Item {
    id: root

    implicitHeight: Config.agentbar.sizes.innerHeight
    implicitWidth: layout.implicitWidth

    /// `[{ project, agents }]`, keyed by project NAME because that is the only
    /// identifier the two sources share — the hub names a project by the
    /// basename of a working directory, and Mesura by its own project title.
    /// Bridge projects come first, in the workspace order `sortedProjects`
    /// already establishes; Mesura's own append after, since they have no
    /// workspace to sort by.
    readonly property var projectGroups: {
        const merged = {};
        const order = [];
        for (const name of AgentService.sortedProjects) {
            merged[name] = AgentService.agents.filter(a => a.project === name);
            order.push(name);
        }
        for (const group of SymmetriaThreads.projectGroups) {
            if (!(group.project in merged)) {
                merged[group.project] = [];
                order.push(group.project);
            }
            merged[group.project] = merged[group.project].concat(group.agents);
        }
        return order.map(name => ({ project: name, agents: merged[name] }));
    }

    RowLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        Repeater {
            // ScriptModel keyed on the project NAME, for the reason
            // `docs/qml-pitfalls.md` records under "Repeater over a
            // freshly-rebuilt JS array resets ALL delegates every update" — and
            // which `ProjectGroup`'s own chip Repeater already answers the same
            // way. This outer one was left on a plain array while the only
            // source pushed rarely; a second source that emits a delta per
            // thread update makes the full teardown constant, and it would tear
            // down every pill in the bar, bridge pills included, whenever an
            // unrelated Mesura thread moved.
            model: ScriptModel {
                values: root.projectGroups
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
