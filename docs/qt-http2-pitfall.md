# Qt HTTP/2 Protocol Error Pitfall

## Problem

Qt 6's `QNetworkAccessManager` enables HTTP/2 by default via ALPN negotiation during TLS handshake. Some servers (notably `ipinfo.io`) advertise HTTP/2 support but have edge cases in their implementation that cause protocol-level errors with Qt's HTTP/2 stack.

**Symptom:** `Requests.get()` silently fails with error: `HTTP/2 protocol error`. The `onSuccess` callback never fires, and without an explicit `onError` callback, the failure is only visible via `qWarning` in the logs.

**Impact on Weather service:** The entire weather initialization chain depends on the first `ipinfo.io` request succeeding to set the `loc` property. When this fails:
```
reload() → ipinfo.io fails → loc stays "" → onLocChanged never fires
→ fetchWeatherData() never runs → cc stays null → UI shows 0°C / cloud_alert
```

The hourly refresh timer calls `fetchWeatherData()` directly, but it early-returns when `loc` is empty, so the weather never recovers without manual intervention (e.g., locking the screen, which triggers a separate `reload()` path).

## Root Cause

Qt's HTTP/2 implementation is less mature than established clients like curl. The protocol negotiation can fail in ways that are hard to reproduce consistently:

- **Connection reuse**: HTTP/2 multiplexes requests over a single connection. Stale or improperly closed connections can cause protocol errors on reconnection.
- **Server-side edge cases**: Some CDNs and API gateways advertise `h2` in ALPN but have subtle incompatibilities with Qt's implementation.
- **Intermittent nature**: Whether the error occurs depends on connection pool state, TLS session resumption, and server-side load balancing — making it appear to work "sometimes."

## Fix

Disable HTTP/2 in `QNetworkRequest` by setting the `Http2AllowedAttribute` to `false`:

```cpp
// plugin/src/Symmetria/requests.cpp
QNetworkRequest request(url);
request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
auto reply = m_manager->get(request);
```

HTTP/1.1 is universally reliable for simple GET requests like weather API calls. The performance difference is negligible for low-frequency requests.

## Diagnostic Approach

If similar issues arise with other HTTP requests:

1. **Check logs for `qWarning`**: `Requests::get` logs failed requests via `qWarning()` when no `onError` callback is provided.
2. **Add temporary error callbacks**: Pass an `onError` function to `Requests.get()` to surface the error message in QML logs.
3. **Test with curl**: If `curl <url>` succeeds but `Requests.get()` fails, the issue is likely Qt's HTTP stack, not the server.
4. **Check Qt version**: HTTP/2 behavior varies across Qt 6.x releases. Some versions have known bugs in the HTTP/2 state machine.

## Related

- Qt bug tracker has multiple reports of HTTP/2 protocol errors with `QNetworkAccessManager`
- The `Http2AllowedAttribute` was introduced in Qt 5.15 and defaults to `true` in Qt 6
- An alternative manager-level approach: set `QNetworkRequest::Http2DirectAttribute` to `false` on a `QSslConfiguration` attached to the manager — but per-request attribute is simpler and more targeted
