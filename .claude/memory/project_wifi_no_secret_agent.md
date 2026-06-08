---
name: project_wifi_no_secret_agent
description: "Why Symmetria's Wi-Fi connect can fail silently — no NetworkManager secret agent"
metadata: 
  node_type: memory
  type: project
  originSessionId: 467b4c9c-745e-4f0e-8f39-e50d201ffd94
---

Symmetria drives Wi-Fi via one-shot `nmcli` invocations (`NmcliCore.executeCommand`) and registers **NO NetworkManager D-Bus secret agent**. `nmtui` and `nm-applet` do register one, which is why they can prompt interactively when NM hits `need-auth`.

Consequence: when NM needs a Wi-Fi secret that is missing/stale/rejected, it fails *instantly* with `no-secrets / "No agents were available for this request"` (visible in `journalctl -u NetworkManager`). There is no one to prompt.

**The bug this caused (fixed 2026-06-07):** `utils/NetworkConnection.qml` had a `hasSavedProfile()` fast path that called `NmcliWifi.connectToNetwork(ssid, "", bssid, null)` with a **null callback** for saved profiles. A saved profile with a bad/stale secret → instant `no-secrets` failure → null callback → **totally silent**, no password dialog. Symptom: "I can only connect to networks I've connected to before." Fix: route ALL secured networks through `connectToNetworkWithPasswordCheck` (tries stored secret first, re-prompts on `needsPassword`). In-code REGRESSION GUARD comment warns against reintroducing the fast path.

**Also fixed same day:** `createConnectionWithPassword` (`services/NmcliWifi.qml`) used to pin `802-11-wireless.bssid` on every new profile (inherited from upstream Caelestia). Pinning makes profiles stop matching after AP reboot / on mesh / when revisiting venues. Removed → profiles now roam (SSID-only) like nmtui's.

Proper long-term fix (not done): implement an actual NM secret agent so NM can prompt Symmetria interactively. Big change (D-Bus service + GetSecrets). See [[feedback_regression_documentation]].
