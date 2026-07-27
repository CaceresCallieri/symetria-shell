# Wi-Fi Connect Flow

Why the Wi-Fi connect path is shaped the way it is, and which "obvious
improvements" are actually regressions. Implementation lives in
`services/NmcliWifi.qml`, `services/NmcliCore.qml`, `utils/NetworkConnection.qml`
and the two password dialogs — read those for the code.

## The core rule

**nmcli's exit code is the result. Nothing infers the outcome.**

`nmcli --wait N device wifi connect …` and `nmcli --wait N connection up uuid …`
block until NetworkManager has either activated the connection or failed it, and
then report that outcome. The callback handed to `connectToNetwork` /
`connectToNetworkWithPasswordCheck` fires exactly once, with the truth, at the
moment it becomes known.

Nothing else is a success or failure signal. In particular `NmcliWifi.active` is
**not** one — see below.

## Symmetria registers no NetworkManager secret agent

`nmtui` and `nm-applet` register a D-Bus secret agent, which is how they can
prompt interactively when NM hits `need-auth`. Symmetria does not. When NM needs
a Wi-Fi secret it does not have, it fails immediately with
`no-secrets / "No agents were available for this request"` — there is nobody to
ask.

The consequence that shapes everything: **Symmetria must inject the psk itself,
in the same command that activates the connection.** Any design where activation
and secret delivery are separate steps will hit `no-secrets`.

Writing a real secret agent (D-Bus service + `GetSecrets`) would remove this
constraint. It is not needed as long as the psk always travels with the connect.

## `active` is not "the network I just connected to"

```qml
readonly property AccessPoint active: networks.find(n => n.active) ?? null
```

That is the **first active access point across all wireless devices**. With more
than one radio it can point at a completely different device than the one an
operation ran on. Two bugs came from treating it as authoritative:

- **Connect** inferred success by polling `active` and comparing SSIDs. With a
  second radio present it compared against the wrong device and declared a
  timeout on a connection NetworkManager had already activated.
- **Disconnect** derived its target from `active` instead of from the network the
  user clicked, and took down the other radio's connection.

Both are fixed by passing the identity explicitly, or reading it from the
operation that owns it. Do not reintroduce either.

## No empty-password probe

Connecting to a secured network with no stored secret asks the user for the
password directly. It does **not** try `nmcli device wifi connect <ssid>` first to
see what happens.

That probe used to exist, and it created a persistent profile with
`autoconnect=yes` and no psk *before* failing. NetworkManager then retried that
dead profile on its own for hours, and every failed attempt left another one
behind to poison the next.

## Profile deletion rules

Deleting connection profiles is destructive and must be authorised by a
definitive failure, never by an inferred one.

| Situation | Action |
|---|---|
| About to connect with a freshly typed password | Delete same-named profiles first — nothing is in flight |
| nmcli returned non-zero **with a secrets error** after we created the profile | Delete it: NM definitively did not connect and the profile carries a known-bad psk with autoconnect on |
| Any other failure | **Leave it alone** |
| Timeout, or "we didn't observe success" | **Leave it alone** — this is what used to destroy working connections |

The historical bug: the dialogs called `forgetNetwork()` on every failure path,
including a 12s timeout that was inferred by polling. On 2026-07-27 that deleted a
connection NetworkManager had reported as `Activation: successful, device
activated` eleven seconds earlier, tearing down working Wi-Fi and reporting
"Connection failed" to the user.

## Do not disconnect the active network before connecting

NetworkManager deactivates the old connection as part of activating a new one on
the same device. An explicit teardown first buys nothing and costs plenty: it
leaves the machine with no network if the new connection then fails, and because
every saved profile has `autoconnect=yes`, NM races to auto-activate some
unrelated saved network in the gap.

## Known limitation: profile settings are lost on password re-entry

`connectWithSecret` deletes every same-named profile before reconnecting, so
per-connection customisation — static IP, and notably **custom DNS** — is
destroyed whenever a password is re-typed for a network that had it.

This matters on connections carrying a DNS override to work around a filtering
ISP resolver: after re-entering the password, the machine silently falls back to
DHCP-provided DNS.

The fix is to `nmcli connection modify <uuid> wifi-sec.psk <pw>` and then
`connection up` that UUID, instead of delete-and-recreate. Note this is *not* the
old `connection add` + `connection up` dance that was removed on 2026-07-15 —
that one failed because a duplicate-name warning made it fall back to activating
the old psk-less profile. Modifying a known UUID has no such ambiguity.

## Testing

`scripts/wifi-testbed.sh` builds a real WPA2-PSK access point on simulated radios
(`mac80211_hwsim` + `hostapd` + `dnsmasq`), so the whole flow can be exercised
against a controllable network without touching the machine's real Wi-Fi card or
costing connectivity.

```bash
sudo ./scripts/wifi-testbed.sh up      # SSID SymmetriaTestAP, password testpass123
sudo ./scripts/wifi-testbed.sh status
sudo ./scripts/wifi-testbed.sh down
```

The AP advertises no gateway and no DNS, so a client association cannot hijack the
real internet path.

**Caveat that shaped two findings above:** while the test bed is up the machine has
*two* connected wireless radios, which is what exposed the `active` ambiguity. That
is a faithful stress test of the code, but remember real hardware here has one
radio — when a failure depends on two radios being connected, say so rather than
reporting it as a user-visible bug.

Ground truth for any run comes from `journalctl -u NetworkManager` (activation
state machine, `audit:` operations showing profile create/delete) and
`qs log -c symmetria` (QML errors). A `ReferenceError` in the shell log is worth
checking first: QML resolves imported types lazily at first use, so a missing
import throws only when the code path actually runs, and neither startup nor
`qmllint` will catch it.
