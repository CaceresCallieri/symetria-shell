#!/bin/bash
# Transcription helper for Symmetria STT
# Sends audio to OpenAI's transcription API and outputs result text.
#
# Usage: STT_API_KEY=<key> stt-transcribe.sh <audio_file> <model>
# stdout: transcribed text (on success)
# stderr: ERROR:<http_code>:<message> (on failure)
# Exit:   0=success, 1=API error, 2=network error, 3=missing args

set -euo pipefail

command -v curl >/dev/null 2>&1 || {
    echo "Error: required command 'curl' not found" >&2
    exit 1
}

AUDIO_FILE="$1"
MODEL="$2"
API_KEY="${STT_API_KEY:-}"

# Unified debug log (shared timeline with QML/Lua/C++)
LOGFILE="${XDG_STATE_HOME:-$HOME/.local/state}/symmetria/debug.log"
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
stt_log() { printf '%s [bash:%s] %s\n' "$(date +%H:%M:%S.%3N)" "$1" "$2" >> "$LOGFILE" 2>/dev/null; }

if [ -z "$AUDIO_FILE" ] || [ -z "$MODEL" ] || [ -z "$API_KEY" ]; then
    echo "ERROR:0:Missing required arguments (or STT_API_KEY not set)" >&2
    exit 3
fi

if [ ! -f "$AUDIO_FILE" ]; then
    echo "ERROR:0:Audio file not found: $AUDIO_FILE" >&2
    exit 3
fi

stt_log "transcribe" "started | file=$AUDIO_FILE model=$MODEL"

# Temp file for response body. CURL_ERR is created later (just before the curl
# call) but must be pre-declared: the EXIT trap references it, and under
# `set -u` an exit between here and that assignment would make the trap fault
# on an unbound variable (leaking RESP_BODY). Empty is safe — `rm -f ""` no-ops.
RESP_BODY=$(mktemp)
CURL_ERR=""
trap 'rm -f "$RESP_BODY" "$CURL_ERR"' EXIT

# Verbatim prompt prevents the LLM-based models (gpt-4o-transcribe) from
# summarizing or paraphrasing speech instead of transcribing it literally.
VERBATIM_PROMPT="Transcribe the following audio verbatim. Do NOT omit, summarize, paraphrase, or clean up anything. Include all words, filler words, repetitions, and false starts exactly as spoken. Output the complete, literal, word-for-word transcript.

The speaker primarily speaks English and Spanish.

When the transcription is long or covers multiple topics, organize it into paragraphs separated by blank lines. Break paragraphs at natural topic shifts or idea transitions. Do NOT add headings, bullet points, or any formatting other than paragraph breaks. Short, single-topic transcriptions should remain as a single paragraph."

# Select the base prompt by model family. gpt-4o-transcribe is an LLM that
# follows the verbatim/paragraph instructions above. whisper-1 instead treats
# `prompt` as a ~224-token style/vocabulary *prime* (continuation context), NOT
# instructions — feeding it the long directive block is inert at best and can
# bias output (it may transcribe fragments of the prompt). So whisper gets only
# a short language hint. whisper-1 is used here for long recordings because it
# chunks audio internally and won't truncate like gpt-4o-transcribe does.
case "$MODEL" in
    whisper*)
        PROMPT="The speaker primarily speaks English and Spanish."
        ;;
    *)
        PROMPT="$VERBATIM_PROMPT"
        ;;
esac

# Append vocabulary hints if provided (comma-separated via env var)
if [ -n "${STT_VOCABULARY_HINTS:-}" ]; then
    # Truncate to ~400 chars to stay within 224-token prompt budget
    if [ ${#STT_VOCABULARY_HINTS} -gt 400 ]; then
        STT_VOCABULARY_HINTS="${STT_VOCABULARY_HINTS:0:400}"
        # Strip trailing partial word (up to last comma). Guard against the
        # case where no comma exists in the truncated string — that would
        # make %,* strip the entire value.
        if [[ "$STT_VOCABULARY_HINTS" == *,* ]]; then
            STT_VOCABULARY_HINTS="${STT_VOCABULARY_HINTS%,*}"
        fi
        stt_log "transcribe" "WARN: vocabulary hints truncated to fit token budget"
    fi
    PROMPT="${PROMPT}

The following proper nouns, technical terms, or names may appear. Use these exact spellings when recognized: ${STT_VOCABULARY_HINTS}"
    stt_log "transcribe" "hints=${STT_VOCABULARY_HINTS}"
fi

CURL_ERR=$(mktemp)
HTTP_CODE=$(curl -s -w '%{http_code}' -o "$RESP_BODY" \
    --connect-timeout 10 \
    --max-time 110 \
    -X POST "https://api.openai.com/v1/audio/transcriptions" \
    -H @- \
    -F "file=@$AUDIO_FILE" \
    -F "model=$MODEL" \
    -F "response_format=text" \
    -F "prompt=$PROMPT" \
    -F "temperature=0" \
    2>"$CURL_ERR" <<< "Authorization: Bearer $API_KEY") || {
        CURL_DETAIL=$(head -c 200 "$CURL_ERR" 2>/dev/null)
        rm -f "$CURL_ERR"
        stt_log "transcribe" "curl-failed | ${CURL_DETAIL:-unknown}"
        echo "ERROR:0:Network error — ${CURL_DETAIL:-curl failed}" >&2
        exit 2
    }
rm -f "$CURL_ERR"

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
        ERR_MSG=$(head -c 200 "$RESP_BODY" 2>/dev/null)
        stt_log "transcribe" "error | http=$HTTP_CODE"
        echo "ERROR:$HTTP_CODE:$ERR_MSG" >&2
        exit 1
        ;;
esac
