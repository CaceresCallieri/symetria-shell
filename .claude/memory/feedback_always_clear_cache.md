---
name: Always clear QML cache yourself
description: After QML/asset changes, always run the cache clear command — don't just tell the user to do it
type: feedback
---

Always clear the QML cache yourself after making QML or asset changes. Don't just instruct the user to do it.

**Why:** The user expects Claude to handle this step directly rather than deferring it.

**How to apply:** After any QML/SVG/asset edit, run `rm -rf ~/.cache/quickshell/qmlcache` as part of the workflow. Still inform the user that a shell restart is needed (since we must not restart the shell process ourselves per CLAUDE.md rules).
