pragma Singleton

import Quickshell

/// Text/byte conversions the QML engine does not provide.
///
/// The QML JS engine exposes NO TextEncoder (verified: `typeof TextEncoder`
/// is "undefined" under Qt 6.11), so UTF-8 encoding has to be done by hand
/// before handing bytes to Qt.btoa.
Singleton {
    id: root

    /// Encode a JS string to its UTF-8 bytes as a plain array of ints.
    /// Surrogate pairs are combined into a single 4-byte sequence.
    /// Empty or nullish input yields an empty array (and `base64("")` yields
    /// `""`, which the callers' `base64 -d` shell path handles as an empty
    /// payload).
    function utf8Bytes(text: string): var {
        if (!text)
            return [];

        const bytes = [];
        for (let i = 0; i < text.length; i++) {
            const cp = text.codePointAt(i);
            // codePointAt() returned an astral character built from a
            // surrogate PAIR — skip the trailing low surrogate so it isn't
            // re-encoded on its own.
            if (cp > 0xFFFF)
                i++;

            // An UNPAIRED surrogate reaching here would otherwise be encoded as
            // a 3-byte CESU-8 sequence (U+D800 -> ED A0 80), which is NOT valid
            // UTF-8. Qt's V4 JSON.stringify does not escape lone surrogates, so
            // one can arrive verbatim; the deprecated Qt.btoa(string) silently
            // dropped it. Emitting invalid UTF-8 is worse than either: it makes
            // the whole appended JSONL file unreadable to json.load/jq, not just
            // the one record. Substitute U+FFFD, per the WHATWG encoding spec.
            if (cp >= 0xD800 && cp <= 0xDFFF) {
                bytes.push(0xEF, 0xBF, 0xBD);
                continue;
            }

            if (cp < 0x80) {
                bytes.push(cp);
            } else if (cp < 0x800) {
                bytes.push(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F));
            } else if (cp < 0x10000) {
                bytes.push(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
            } else {
                bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
            }
        }
        return bytes;
    }

    /// Base64-encode a string as UTF-8.
    ///
    /// Use this instead of `Qt.btoa(someString)`. That overload is deprecated
    /// in Qt 6 (it warns on EVERY call — the lock-screen heartbeat alone fired
    /// it every 2s while locked) because its output differs from the Web API's
    /// latin1-based btoa. Qt's string overload happens to encode as UTF-8, so
    /// routing through utf8Bytes() is byte-for-byte identical to the old
    /// behaviour — verified against accented + multi-byte input. This is a
    /// deprecation fix, NOT a format change: existing base64 payloads decode
    /// the same.
    ///
    /// Callers pipe the result through `base64 -d` in a shell command; the
    /// base64 alphabet (A-Za-z0-9+/=) contains no shell metacharacters, which
    /// is the whole reason the payload is encoded before crossing `sh -c`.
    function base64(text: string): string {
        // String() is REQUIRED, not defensive. Qt.btoa's array-like overload
        // returns a wrapper OBJECT (typeof "object"), unlike the deprecated
        // string overload which returns a real JS string. Callers put the
        // result into Process.environment maps and shell template literals,
        // where an object serialises to something other than the base64 text.
        return String(Qt.btoa(root.utf8Bytes(text)));
    }
}
