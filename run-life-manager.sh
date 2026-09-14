#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi

: "${OPENAI_API_KEY:?Set OPENAI_API_KEY or add it to .env.local}"
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

API="https://api.openai.com/v1/agents"
AGENT_ID="agent_ab723545fb484badafe97a5593ffcdd0954b67630a99464eba"
PROJECT_ID="proj_KxpSLJO5HxztrlzENq60G8re"
PROMPT="${*:-Help me plan my day: ask one clarifying question, then suggest three practical priorities.}"
PAYLOAD="$(jq -n --arg id "$AGENT_ID" --arg model "gpt-5.6-luna" --arg instructions "Официальный тон, пунктуальность, память, остроумие и критическое мышление." --arg input "$PROMPT" '{agent_id:$id,agent:{model:$model,instructions:$instructions,reasoning:{effort:"low",summary:"auto"},text:{format:{type:"text"},verbosity:"low"}},environment:{type:"openai_hosted"},input:$input,stream:true}')"

echo "Starting Life Manager (project: $PROJECT_ID) ..." >&2
curl --no-buffer --fail-with-body -sS -X POST "$API/sessions" \
  -H "OpenAI-Beta: agents=v1" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" == data:* ]]; then
      event="${line#data: }"
      if jq -e . >/dev/null 2>&1 <<<"$event"; then
        type="$(jq -r '.type // empty' <<<"$event")"
        case "$type" in
          agent.session.turn.failed|agent.session.turn.cancelled)
            echo "Session ended with $type" >&2 ;;
          agent.session.turn.completed)
            echo "Session turn completed." >&2 ;;
        esac
      fi
    fi
  done
