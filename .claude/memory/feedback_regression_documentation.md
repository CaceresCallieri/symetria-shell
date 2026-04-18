---
name: Document regressions from code review fixes
description: When a code review fix causes a regression, add inline comments and update docs to prevent re-application
type: feedback
---

When a code review "fix" causes a regression, always document it in three places:
1. Inline comment at the affected code explaining what was tried and why it's wrong
2. Project docs (e.g., qml-pitfalls.md) if the lesson generalizes
3. Global CLAUDE.md has a "Regression Documentation" section codifying this

**Why:** A code review agent incorrectly changed `required property var modelData` to `required modelData` in QML Repeater delegates, following the shadowing pitfall rule without understanding the exception for model-injected properties on generic types. This caused workspace icons to disappear. Without documentation, future agents will attempt the same "fix."

**How to apply:** After any regression revert, add a comment explaining "Why does this look wrong but is actually correct?" before proceeding with the commit.
