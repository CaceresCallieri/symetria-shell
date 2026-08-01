---
name: project_wifi_no_secret_agent
description: "Why Symmetria's Wi-Fi connect kept failing, how it was finally fixed and verified (2026-07-27)"
metadata:
  node_type: memory
  type: project
  originSessionId: 467b4c9c-745e-4f0e-8f39-e50d201ffd94
  modified: 2026-07-27T18:20:34.718Z
---

**RESOLVED 2026-07-27** (commit `506290f1`), verified end-to-end on a virtual AP.
Design rationale + regression guards now live in `docs/wifi-connect-flow.md` —
read that first; this memory only records what is not derivable from the repo.

**The actual root cause of "the password dialog spins forever", after three
failed rounds of fixes:** `modules/bar/popouts/WirelessPassword.qml` called
`NetworkConnection.connectWithPassword` but never imported `qs.utils`. The click
handler set `connecting = true` and then threw `ReferenceError: NetworkConnection
is not defined` before running any nmcli command. QML resolves imported types
lazily at first use, so this broke neither startup nor `qmllint` — it appeared
only in `qs log -c symmetria`, only when that path ran. The control-center dialog
had the import, which is why the bug looked path-specific.

**Why three rounds of fixes missed it:** all three debugged the nmcli layer
(psk injection, profile deletion, error-string matching). The bar popout never
reached that layer. **Lesson: before fixing the layer you suspect, prove the
call even arrives there.** `qs log` for ReferenceErrors is a ~10-second check
that would have ended this months earlier.

**Second root cause, exposed once the import was fixed:** success/failure was
inferred by polling `NmcliWifi.active` across three overlapping timers instead of
read from nmcli's exit code. Measured: NM activated in 0.5s, the poll window
closed at 3.0s, and the 12s timeout then *deleted the working profile*.

**How it was verified — reusable method:** `scripts/wifi-testbed.sh` builds a real
WPA2 AP on `mac80211_hwsim` radios, so the flow is testable without touching
`wlan0` or costing connectivity (the agent runs locally; its API calls go over
that card). Ground truth = `journalctl -u NetworkManager` (`audit:` lines show
profile create/delete; state machine shows real activation) + `qs log`. Use this
for any future network work. Caveat: the test bed means TWO connected radios,
which is what exposed the `active` ambiguity — do not report a two-radio-only
failure as a user-visible bug on this single-radio machine.

**Open follow-up:** `connectWithSecret` deletes same-named profiles before
reconnecting, so re-typing a password destroys per-connection settings — notably
the **custom DNS override on the Fibertel profile** (`1.1.1.1`, needed because the
ISP resolver filters domains, see global CLAUDE.md). Fix is `connection modify
<uuid> wifi-sec.psk` + `connection up` instead of delete-and-recreate. Not the
old `connection add` + `up` dance removed 2026-07-15 — modifying a known UUID has
no duplicate-name ambiguity.

Still true: Symmetria registers **no NM secret agent**, so it must inject the psk
in the same command that activates. See [[feedback_regression_documentation]].
