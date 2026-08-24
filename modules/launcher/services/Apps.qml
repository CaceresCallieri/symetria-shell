pragma Singleton

import qs.config
import qs.utils
import Symmetria
import Quickshell

Searcher {
    id: root

    // Wrapper script for launchArgs below. Chdir to the entry's Path, or to $HOME when
    // that is empty or gone, or to / as a last resort, then exec the real command.
    // Arguments arrive as positional parameters, so no quoting is involved.
    readonly property string chdirWrapper: 'if [ -z "$1" ] || ! cd "$1" 2>/dev/null; then cd "$HOME" 2>/dev/null || cd /; fi; shift; exec "$@"'

    function launchArgs(entry: DesktopEntry): list<string> {
        const command = entry.runInTerminal ? [...Config.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command] : [...entry.command];

        // WORKAROUND: launch through `sh -c` instead of the ProcessContext object form of
        // execDetached. Two separate defects make the object form unusable here.
        //
        // 1. `Quickshell.execDetached({command, workingDirectory})` throws "Could not
        //    convert argument 0 from [object Object] to qs::io::process::ProcessContext"
        //    when the quickshell build and the installed Qt disagree on a patch release
        //    (built against Qt 6.11.0, system runs Qt 6.11.1). The list form of
        //    execDetached is unaffected, which is why every other call site in this shell
        //    keeps working. Do NOT revert to the object form to "clean this up".
        // 2. The list form cannot set a working directory, so the child inherits the cwd
        //    of whatever started the shell. When that directory is later removed - a git
        //    worktree, a build sandbox - app2unit falls back to `systemd-run --same-dir`,
        //    which aborts with "Failed to get current working directory". No unit is
        //    created and nothing reaches the journal, so every launch fails in complete
        //    silence.
        //
        // execDetached discards the child's stdout and stderr - a child that writes to
        // stderr and exits non-zero produces no output anywhere. The wrapper therefore
        // guarantees a usable directory rather than reporting a bad one, because a
        // report would go nowhere.
        //
        // Removing this needs both halves covered, not only the Qt one. A rebuilt
        // quickshell restores the object form, but that form reproduces defect 2 whenever
        // workingDirectory is the empty string - the common case, since most entries carry
        // no Path= - because the child then inherits the shell's cwd exactly as before.
        // Any replacement must still substitute a valid directory for those entries.
        return ["sh", "-c", root.chdirWrapper, "symmetria-launch", entry.workingDirectory, "app2unit", "--", ...command];
    }

    function launch(entry: DesktopEntry): void {
        appDb.incrementFrequency(entry.id);
        Quickshell.execDetached(root.launchArgs(entry));
    }

    function search(search: string): list<var> {
        const prefix = Config.launcher.specialPrefix;

        if (search.startsWith(`${prefix}i `)) {
            keys = ["id", "name"];
            weights = [0.9, 0.1];
        } else if (search.startsWith(`${prefix}c `)) {
            keys = ["categories", "name"];
            weights = [0.9, 0.1];
        } else if (search.startsWith(`${prefix}d `)) {
            keys = ["comment", "name"];
            weights = [0.9, 0.1];
        } else if (search.startsWith(`${prefix}e `)) {
            keys = ["execString", "name"];
            weights = [0.9, 0.1];
        } else if (search.startsWith(`${prefix}w `)) {
            keys = ["startupClass", "name"];
            weights = [0.9, 0.1];
        } else if (search.startsWith(`${prefix}g `)) {
            keys = ["genericName", "name"];
            weights = [0.9, 0.1];
        } else if (search.startsWith(`${prefix}k `)) {
            keys = ["keywords", "name"];
            weights = [0.9, 0.1];
        } else {
            keys = ["name"];
            weights = [1];

            if (!search.startsWith(`${prefix}t `))
                return query(search).map(e => e.entry);
        }

        const results = query(search.slice(prefix.length + 2)).map(e => e.entry);
        if (search.startsWith(`${prefix}t `))
            return results.filter(a => a.runInTerminal);
        return results;
    }

    function selector(item: var): string {
        return keys.map(k => item[k]).join(" ");
    }

    list: appDb.apps
    useFuzzy: Config.launcher.useFuzzy.apps

    AppDb {
        id: appDb

        path: `${Paths.state}/apps.sqlite`
        entries: DesktopEntries.applications.values.filter(a => !Config.launcher.hiddenApps.includes(a.id))
    }
}
