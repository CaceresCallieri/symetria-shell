#!/bin/bash
# Transcription helper for Symmetria STT
# Sends audio to OpenAI's transcription API and outputs result text.
#
# Usage: STT_API_KEY=<key> stt-transcribe.sh <audio_file> <language> <model>
# stdout: transcribed text (on success)
# stderr: ERROR:<http_code>:<message> (on failure)
# Exit:   0=success, 1=API error, 2=network error, 3=missing args

set -e

AUDIO_FILE="$1"
LANGUAGE="$2"
MODEL="$3"
API_KEY="${STT_API_KEY:-}"

# Unified debug log (shared timeline with QML/Lua/C++)
LOGFILE="${XDG_STATE_HOME:-$HOME/.local/state}/symmetria/debug.log"
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
stt_log() { printf '%s [bash:%s] %s\n' "$(date +%H:%M:%S.%3N)" "$1" "$2" >> "$LOGFILE" 2>/dev/null; }

if [ -z "$AUDIO_FILE" ] || [ -z "$LANGUAGE" ] || [ -z "$MODEL" ] || [ -z "$API_KEY" ]; then
    echo "ERROR:0:Missing required arguments (or STT_API_KEY not set)" >&2
    exit 3
fi

if [ ! -f "$AUDIO_FILE" ]; then
    echo "ERROR:0:Audio file not found: $AUDIO_FILE" >&2
    exit 3
fi

stt_log "transcribe" "started | file=$AUDIO_FILE lang=$LANGUAGE model=$MODEL"

# Temp file for response body
RESP_BODY=$(mktemp)
trap 'rm -f "$RESP_BODY"' EXIT

HTTP_CODE=$(curl -s -w '%{http_code}' -o "$RESP_BODY" \
    --connect-timeout 10 \
    --max-time 110 \
    -X POST "https://api.openai.com/v1/audio/transcriptions" \
    -H "Authorization: Bearer $API_KEY" \
    -F "file=@$AUDIO_FILE" \
    -F "model=$MODEL" \
    -F "response_format=text" \
    -F "language=$LANGUAGE" \
    2>/dev/null) || {
        echo "ERROR:0:Network error (curl failed)" >&2
        exit 2
    }

case "$HTTP_CODE" in
    200)
        RESP_LEN=$(wc -c < "$RESP_BODY")
        stt_log "transcribe" "success | len=$RESP_LEN"
        cat "$RESP_BODY"
        exit 0
        ;;
    401)
        stt_log "transcribe" "error | http=401"
        echo "ERROR:401:Authentication failed - check API key" >&2
        exit 1
        ;;
    429)
        stt_log "transcribe" "error | http=429"
        echo "ERROR:429:Rate limit or quota exceeded" >&2
        exit 1
        ;;
    5[0-9][0-9])
        stt_log "transcribe" "error | http=$HTTP_CODE"
        echo "ERROR:$HTTP_CODE:API server error" >&2
        exit 1
        ;;
    *)
        # Try to extract error message from response
        ERR_MSG=$(cat "$RESP_BODY" 2>/dev/null | head -c 200)
        stt_log "transcribe" "error | http=$HTTP_CODE"
        echo "ERROR:$HTTP_CODE:$ERR_MSG" >&2
        exit 1
        ;;
esac
