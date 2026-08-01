---
name: pipewire-pulse-lockout
description: "Recurring \"no audio\" = pipewire-pulse start-limit-hit; diagnosis pattern and the drop-in that self-heals it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 77d7ef0a-da60-4f28-885a-cea070eb8b47
  modified: 2026-08-01T06:20:01.447Z
---

Twice (2026-07-12, 2026-07-13) all desktop audio died because `pipewire-pulse.service` hit systemd's `start-limit-hit`: external stop-bursts (portal/audio fix sequences racing socket activation — five clean starts/exits within a second) tripped the default 5-starts/10s limit, leaving service AND socket dead. PipeWire itself keeps running, so the tell is split-brain: `wpctl` works, `pactl` gets Connection refused.

**Why:** the lockout, not the stops, is what kills audio persistently — every PulseAudio client (browsers, Discord, media) needs the pulse socket.

**How to apply:** if the user reports no audio, first rule out a *stale STT duck* — `stt.ducking.volume` is now 0, so a shell crash mid-recording leaves the sink at absolute 0 while unmuted, which looks identical to this lockout. `wpctl get-volume @DEFAULT_AUDIO_SINK@` reading 0.00 while `pactl info` still answers means a stale duck, not PipeWire (see the diagnostic note in `services/AudioDucking.qml`). Otherwise check `systemctl --user is-active pipewire-pulse.service pipewire-pulse.socket`. Recover with `systemctl --user reset-failed pipewire-pulse.service pipewire-pulse.socket && systemctl --user start pipewire-pulse.socket pipewire-pulse.service`. A permanent drop-in (`~/.dotfiles/.config/systemd/user/pipewire-pulse.service.d/override.conf`, commit 424690b) sets `StartLimitIntervalSec=0` so the service self-heals on the next client connection — if audio still dies with that in place, the killer is actively stopping it; check the journal around the stop timestamps.

The original stop-initiator was never definitively pinned: correlated with portal restarts (`xdg-desktop-portal-hyprland` fresh PID) and shell-restart activity. `/fix-screenshare` restarts portals only, never PipeWire.
