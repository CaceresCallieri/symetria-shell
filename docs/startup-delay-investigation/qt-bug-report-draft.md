# Qt Bug Report — Ready to File

**File at:** https://bugreports.qt.io
**Component:** QML: Declarative and Javascript Engine
**Type:** Bug
**Affects Version:** 6.11.0
**Last Working Version:** 6.10.2

---

## Title

[Reg 6.10->6.11] Binding evaluation / component tree creation ~10x slower for large synchronous QML component trees

## Description

### What I did

Upgraded Qt from 6.10.2 to 6.11.0 on Arch Linux. Launched the same QML application (a Wayland desktop shell using Quickshell framework) with identical QML source files and measured startup time using a heartbeat Timer.

### What I expected

Similar startup time as on Qt 6.10.2 (~7–10 seconds for the full component tree).

### What actually happened

The event loop freezes for **80–93 seconds** before the first Timer heartbeat fires. The application is completely unresponsive during this time. After the freeze, the event loop resumes normally with ~500ms heartbeat intervals.

### Measured Results

| Configuration | Event Loop Freeze |
|---|---|
| Qt 6.10.2, same binary, same QML | **7–10 seconds** |
| Qt 6.11.0, same binary, same QML | **80–93 seconds** |

### Isolation

We systematically eliminated all variables except Qt version:

1. **Application binary:** Built the same application source (Quickshell, commit `1e4d804`) against Qt 6.11.0 — still 86s. Built current version against 6.11.0 — 91s. (**Application version is NOT a factor.**)
2. **QML source code:** Identical QML files on both Qt versions. Code from 4 weeks prior gives the same ~97s on Qt 6.11.0. (**QML code is NOT a factor.**)
3. **QML bytecode cache:** Cold cache (cleared) and warm cache both show ~90s on Qt 6.11.0. (**Cache/compilation is NOT a factor.** This is runtime binding evaluation.)
4. **Component isolation:**
   - Full application: **91s**
   - Only the main component sub-tree (Panels — 12 module directories, ~160 transitive QML types, ~1,400 properties): **91s**
   - Main sub-tree stubbed to an empty Item: **672ms**
   - Everything else without the main sub-tree: **671ms**

**The regression is in evaluating the binding graph of a large synchronous component tree.**

### Architecture of the Affected Code Path

The pattern that triggers the regression:

1. A top-level component synchronously instantiates a **Panels** component
2. Panels imports 12 QML module directories (each containing 3–16 files)
3. Total transitive cascade: ~160 QML types, ~1,400 property declarations with binding expressions
4. The framework performs a synchronous reload walk — recursively visiting every QObject child and evaluating all bindings
5. This is non-deferrable (async Loader within the parent container is not supported)

Most QML applications don't hit this because they load components lazily. This application creates the entire tree synchronously.

### Suspected Root Cause

Based on the Qt 6.11.0 release notes, the most likely candidates:

**1. "Do not store type references for properties" (QQmlPropertyCache change)**

This is the most significant internal QML engine change in 6.11 — modifying how `QQmlPropertyCache` stores property metadata to enable cyclic type references. If property type resolution now requires runtime lookups instead of using pre-stored references, this cost compounds super-linearly across a large binding cascade.

**2. Property shadowing runtime enforcement (virtual/override/final)**

Qt 6.11's new `virtual`/`override`/`final` property keywords include runtime enforcement. Our startup logs show these warnings:

```
qt.qml.propertyCache.append: Member data of the object ClippingRectangle_QMLTYPE_177
overrides a member of the base object. Consider renaming it or adding final or override specifier
```

If shadowing checks occur per-property-access rather than once at type registration, this would add significant overhead.

### Standalone Reproducer

A minimal CMake/QML project is provided that generates a deep synchronous component tree with cross-referencing bindings. See the attached `QTBUG-XXXXXX/` directory.

To test:
```bash
cmake -B build -G Ninja
cmake --build build
# Run and compare output on Qt 6.10.2 vs 6.11.0:
./build/qtbug-repro
```

### Environment

- OS: Arch Linux, kernel 6.19.10-zen1-1-zen
- GPU: AMD Radeon 860M (radeonsi, Mesa 26.0.3)
- Qt: qt6-base 6.11.0-1, qt6-declarative 6.11.0-1 (Arch packages)
- Application: Quickshell 0.2.1-git (Wayland compositor shell framework)
- Compositor: Hyprland

### Workaround

Downgrade to Qt 6.10.2. No QML-level workaround exists.
