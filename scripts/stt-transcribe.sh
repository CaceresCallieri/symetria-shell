#!/bin/sh
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

if [ -z "$AUDIO_FILE" ] || [ -z "$LANGUAGE" ] || [ -z "$MODEL" ] || [ -z "$API_KEY" ]; then
    echo "ERROR:0:Missing required arguments (or STT_API_KEY not set)" >&2
    exit 3
fi

if [ ! -f "$AUDIO_FILE" ]; then
    echo "ERROR:0:Audio file not found: $AUDIO_FILE" >&2
    exit 3
fi

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
        cat "$RESP_BODY"
        exit 0
        ;;
    401)
        echo "ERROR:401:Authentication failed - check API key" >&2
        exit 1
        ;;
    429)
        echo "ERROR:429:Rate limit or quota exceeded" >&2
        exit 1
        ;;
    5[0-9][0-9])
        echo "ERROR:$HTTP_CODE:API server error" >&2
        exit 1
        ;;
    *)
        # Try to extract error message from response
        ERR_MSG=$(cat "$RESP_BODY" 2>/dev/null || true | head -c 200)
        echo "ERROR:$HTTP_CODE:$ERR_MSG" >&2
        exit 1
        ;;
esac
