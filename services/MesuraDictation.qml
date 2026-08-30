pragma Singleton

import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// Bidirectional transport between the Shell-owned STT job and Mesura's local
/// dictation broker. The helper discovers every local Mesura process, while
/// this singleton keeps the one active session and maps wire events to QML.
Singleton {
    id: root

    readonly property var session: _session
    readonly property int peerPid: _peerPid
    readonly property bool connected: _peerPid > 0 && _connectedPeers[_peerPid] === true
    readonly property var protocolVersion: ({
            major: 1,
            minor: 5
        })

    property var _session: null
    property int _peerPid: -1
    property var _connectedPeers: ({})
    property var _announcedMesuraSessions: ({})
    property var _announcedSessionOrder: []
    property var _cancelledReservations: ({})
    property var _cancelledReservationOrder: []
    property var _appliedActionIds: ({})
    property var _appliedActionOrder: []
    property var _pendingReservation: null
    property int _commandCounter: 0

    signal reservationConfirmed(int peerPid, var session)
    signal reservationFailed(string sessionId, string detail)
    signal externalSessionRequested(int peerPid, var session)
    signal controlRequested(string sessionId, string commandId, string action)
    signal vocabularyRequested(string sessionId, string commandId, string action, string word, int index)
    signal receiptReceived(int peerPid, var receipt)
    signal sessionChangedForPeer(int peerPid, var session)
    signal peerConnected(int peerPid)
    signal peerDisconnected(int peerPid, string detail)

    function _newCommandId(kind: string): string {
        _commandCounter++;
        return `shell-${kind}-${Date.now()}-${_commandCounter}`;
    }

    function _send(peer: int, message: var, requestId: string): bool {
        if (_connectedPeers[peer] !== true || !clientProcess.running) {
            if (requestId !== "")
                reservationFailed(message.sessionId ?? "", "Mesura dictation is unavailable");
            return false;
        }
        clientProcess.write(JSON.stringify({
            type: "send",
            peerPid: peer,
            requestId: requestId,
            message: message
        }) + "\n");
        return true;
    }

    function reserve(peer: int, sessionId: string, source: string): bool {
        if (_pendingReservation !== null)
            return false;
        const commandId = _newCommandId("reserve");
        _pendingReservation = {
            peerPid: peer,
            sessionId: sessionId,
            commandId: commandId
        };
        const sent = _send(peer, {
            type: "dictation.reserve.request",
            protocolVersion: root.protocolVersion,
            sessionId: sessionId,
            commandId: commandId,
            createdAt: new Date().toISOString(),
            source: source
        }, commandId);
        if (!sent)
            _pendingReservation = null;
        else
            reservationTimer.start();
        return sent;
    }

    function cancelReservation(sessionId: string): void {
        const cancelled = Object.assign({}, _cancelledReservations);
        cancelled[sessionId] = true;
        const order = _cancelledReservationOrder.filter(id => id !== sessionId).concat([sessionId]);
        while (order.length > 64)
            delete cancelled[order.shift()];
        _cancelledReservations = cancelled;
        _cancelledReservationOrder = order;
        if (_pendingReservation?.sessionId === sessionId) {
            _pendingReservation = null;
            reservationTimer.stop();
        }
    }

    function _failPendingReservation(detail: string): void {
        const pending = _pendingReservation;
        if (pending === null)
            return;
        cancelReservation(pending.sessionId);
        reservationFailed(pending.sessionId, detail);
    }

    function sendControl(action: string): string {
        if (_session === null || _peerPid <= 0)
            return "";
        return sendControlTo(_peerPid, _session, action);
    }

    function sendControlTo(peer: int, targetSession: var, action: string): string {
        if (targetSession === null || peer <= 0)
            return "";
        const commandId = _newCommandId(action);
        const sent = _send(peer, {
            type: "dictation.control",
            protocolVersion: root.protocolVersion,
            sessionId: targetSession.sessionId,
            commandId: commandId,
            createdAt: new Date().toISOString(),
            action: action
        }, "");
        return sent ? commandId : "";
    }

    function acceptSession(peer: int, acceptedSession: var): void {
        _peerPid = peer;
        _session = acceptedSession;
        _refreshPresentationLease();
    }

    function _relinquishPresentation(): void {
        presentationLeaseTimer.stop();
        if (_session?.presentation?.mesuraOwnsPresentation !== true)
            return;
        _session = Object.assign({}, _session, {
            presentation: {
                mesuraOwnsPresentation: false,
                leaseExpiresAt: null
            }
        });
    }

    function _refreshPresentationLease(): void {
        presentationLeaseTimer.stop();
        if (_session?.presentation?.mesuraOwnsPresentation !== true)
            return;
        const expiresAt = Date.parse(_session.presentation.leaseExpiresAt ?? "");
        if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
            _relinquishPresentation();
            return;
        }
        presentationLeaseTimer.interval = Math.max(1, expiresAt - Date.now());
        presentationLeaseTimer.start();
    }

    function setMode(mode: string): void {
        if (_session === null || _peerPid <= 0)
            return;
        _send(_peerPid, {
            type: "dictation.mode.set",
            protocolVersion: root.protocolVersion,
            sessionId: _session.sessionId,
            commandId: _newCommandId("mode"),
            createdAt: new Date().toISOString(),
            mode: mode
        }, "");
    }

    function addVocabulary(word: string): void {
        _sendVocabulary("add", {
            word: word
        });
    }

    function removeVocabulary(index: int): void {
        _sendVocabulary("remove", {
            index: index
        });
    }

    function toggleVocabulary(): void {
        _sendVocabulary("toggle", {});
    }

    function acknowledgeAction(actionKind: string, acknowledgedCommandId: string): void {
        if (_session === null || _peerPid <= 0 || acknowledgedCommandId === "")
            return;
        const applied = Object.assign({}, _appliedActionIds);
        const actionKey = `${_session.sessionId}:${acknowledgedCommandId}`;
        applied[actionKey] = true;
        const order = _appliedActionOrder.filter(key => key !== actionKey).concat([actionKey]);
        while (order.length > 256)
            delete applied[order.shift()];
        _appliedActionIds = applied;
        _appliedActionOrder = order;
        _send(_peerPid, {
            type: "dictation.action.acknowledge",
            protocolVersion: root.protocolVersion,
            sessionId: _session.sessionId,
            commandId: _newCommandId("acknowledge"),
            createdAt: new Date().toISOString(),
            actionKind: actionKind,
            acknowledgedCommandId: acknowledgedCommandId
        }, "");
    }

    function _sendVocabulary(action: string, payload: var): void {
        if (_session === null || _peerPid <= 0)
            return;
        _send(_peerPid, Object.assign({
            type: `dictation.vocabulary.${action}`,
            protocolVersion: root.protocolVersion,
            sessionId: _session.sessionId,
            commandId: _newCommandId("vocabulary"),
            createdAt: new Date().toISOString()
        }, payload), "");
    }

    function updateState(job: var): void {
        if (!job?._mesuraIntegrated || _session === null || job.sessionId !== _session.sessionId || job._mesuraPeerPid !== _peerPid)
            return;
        const phase = job._canonicalMesuraPhase();
        _send(_peerPid, {
            type: "dictation.state.update",
            protocolVersion: root.protocolVersion,
            sessionId: job.sessionId,
            commandId: _newCommandId("state"),
            createdAt: new Date().toISOString(),
            phase: phase,
            elapsedMs: Math.max(0, Math.round(job.elapsedSeconds * 1000)),
            audioLevel: phase === "recording" ? Math.max(0, Math.min(1, job.audioLevel)) : null,
            graceRemainingMs: phase === "grace" ? job._graceRemainingMs : null
        }, "");
    }

    function deliver(job: var): bool {
        if (!job?._mesuraIntegrated || _session === null || job.sessionId !== _session.sessionId || job._mesuraPeerPid !== _peerPid || job.transcribedText.trim() === "")
            return false;
        const commandId = ensureDeliveryCommandId(job);
        return _send(_peerPid, {
            type: "dictation.deliver",
            protocolVersion: root.protocolVersion,
            sessionId: job.sessionId,
            commandId: commandId,
            createdAt: new Date().toISOString(),
            target: _session.target,
            mode: job.activeDeliveryChoice,
            text: job.transcribedText
        }, "");
    }

    function ensureDeliveryCommandId(job: var): string {
        if (job._mesuraDeliveryCommandId === "")
            job._mesuraDeliveryCommandId = _newCommandId("deliver");
        return job._mesuraDeliveryCommandId;
    }

    function _applySnapshot(peer: int, nextSession: var): void {
        sessionChangedForPeer(peer, nextSession);
        if (nextSession === null)
            return;

        if (_cancelledReservations[nextSession.sessionId] === true) {
            const cancelled = Object.assign({}, _cancelledReservations);
            delete cancelled[nextSession.sessionId];
            _cancelledReservations = cancelled;
            _cancelledReservationOrder = _cancelledReservationOrder.filter(id => id !== nextSession.sessionId);
            sendControlTo(peer, nextSession, "cancel");
            return;
        }

        const pending = _pendingReservation;
        if (pending !== null && pending.peerPid === peer && pending.sessionId === nextSession.sessionId) {
            _pendingReservation = null;
            reservationTimer.stop();
            acceptSession(peer, nextSession);
            reservationConfirmed(peer, nextSession);
            return;
        }

        const activePhase = nextSession.phase !== "completed" && nextSession.phase !== "failed" && nextSession.phase !== "cancelled";
        if (nextSession.source === "mesura" && activePhase && _announcedMesuraSessions[nextSession.sessionId] !== true) {
            const announced = Object.assign({}, _announcedMesuraSessions);
            announced[nextSession.sessionId] = true;
            const order = _announcedSessionOrder.filter(id => id !== nextSession.sessionId).concat([nextSession.sessionId]);
            while (order.length > 64)
                delete announced[order.shift()];
            _announcedMesuraSessions = announced;
            _announcedSessionOrder = order;
            externalSessionRequested(peer, nextSession);
            return;
        }

        if (_peerPid === peer && _session?.sessionId === nextSession.sessionId) {
            _session = nextSession;
            _refreshPresentationLease();
        }

        if (!activePhase) {
            const announced = Object.assign({}, _announcedMesuraSessions);
            delete announced[nextSession.sessionId];
            _announcedMesuraSessions = announced;
            _announcedSessionOrder = _announcedSessionOrder.filter(id => id !== nextSession.sessionId);
            if (nextSession.lastControl === undefined && nextSession.lastVocabulary === undefined) {
                const applied = {};
                for (const key of Object.keys(_appliedActionIds)) {
                    if (!key.startsWith(`${nextSession.sessionId}:`))
                        applied[key] = true;
                }
                _appliedActionIds = applied;
                _appliedActionOrder = _appliedActionOrder.filter(key => !key.startsWith(`${nextSession.sessionId}:`));
            }
        }
    }

    function _onLine(data: string): void {
        const line = data.trim();
        if (line === "")
            return;
        let event;
        try {
            event = JSON.parse(line);
        } catch (error) {
            Logger.log("qml", "stt", "mesura-client-malformed | " + line.slice(0, 120));
            return;
        }
        const peer = Number(event.peerPid ?? -1);
        if (event.type === "peer.connected") {
            const peers = Object.assign({}, _connectedPeers);
            peers[peer] = true;
            _connectedPeers = peers;
            peerConnected(peer);
        } else if (event.type === "peer.disconnected") {
            const peers = Object.assign({}, _connectedPeers);
            delete peers[peer];
            _connectedPeers = peers;
            if (_peerPid === peer)
                _relinquishPresentation();
            if (_pendingReservation?.peerPid === peer)
                _failPendingReservation(event.detail ?? "Mesura disconnected during reservation");
            peerDisconnected(peer, event.detail ?? "Mesura disconnected");
        } else if (event.type === "snapshot") {
            const peers = Object.assign({}, _connectedPeers);
            peers[peer] = true;
            _connectedPeers = peers;
            _applySnapshot(peer, event.session ?? null);
        } else if (event.type === "control") {
            const actionKey = `${event.sessionId ?? ""}:${event.commandId ?? ""}`;
            if (_appliedActionIds[actionKey] === true)
                acknowledgeAction("control", event.commandId ?? "");
            else
                controlRequested(event.sessionId ?? "", event.commandId ?? "", event.action ?? "");
        } else if (event.type === "vocabulary") {
            const actionKey = `${event.sessionId ?? ""}:${event.commandId ?? ""}`;
            if (_appliedActionIds[actionKey] === true)
                acknowledgeAction("vocabulary", event.commandId ?? "");
            else
                vocabularyRequested(event.sessionId ?? "", event.commandId ?? "", event.action ?? "", event.word ?? "", Number(event.index ?? -1));
        } else if (event.type === "receipt") {
            const receipt = event.receipt ?? {};
            Logger.log("qml", "stt", `mesura-receipt | peer=${peer} | session=${receipt.sessionId ?? ""} | command=${receipt.commandId ?? ""} | outcome=${receipt.outcome ?? ""} | code=${receipt.code ?? ""}`);
            receiptReceived(peer, event.receipt);
        } else if (event.type === "client.error" && _pendingReservation !== null && (event.requestId === _pendingReservation.commandId || peer === _pendingReservation.peerPid)) {
            _failPendingReservation(event.detail ?? "Mesura dictation is unavailable");
        }
    }

    Process {
        id: clientProcess
        command: [Qt.resolvedUrl("../scripts/mesura-dictation-client.py").toString().replace(/^file:\/\//, "")]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root._onLine(data)
        }
        stderr: SplitParser {
            onRead: data => Logger.log("qml", "stt", "mesura-client-stderr | " + data.trim())
        }
        onExited: (code, status) => {
            root._connectedPeers = {};
            root._relinquishPresentation();
            if (root._pendingReservation !== null)
                root._failPendingReservation("Mesura dictation helper stopped");
            if (!restartTimer.running)
                restartTimer.start();
        }
    }

    Timer {
        id: presentationLeaseTimer
        onTriggered: root._relinquishPresentation()
    }

    Timer {
        id: reservationTimer
        interval: 5500
        onTriggered: root._failPendingReservation("Mesura did not confirm the dictation target")
    }

    Timer {
        id: restartTimer
        interval: 1000
        onTriggered: clientProcess.running = true
    }

    Component.onCompleted: clientProcess.running = true
}
