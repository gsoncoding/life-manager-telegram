#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi
: "${OPENAI_API_KEY:?OPENAI_API_KEY is required}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

TG="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
AGENTS="https://api.openai.com/v1/agents"
STATE="$ROOT_DIR/.telegram-sessions"
mkdir -p "$STATE"
offset=0

send_message() {
  local chat_id="$1" text="$2"
  curl -sS "$TG/sendMessage" --data-urlencode "chat_id=$chat_id" --data-urlencode "text=$text" >/dev/null
}

reply_from_agents() {
  local user_id="$1" prompt="$2" session_id payload stream_file answer
  session_id=""
  # Start a fresh Agents session for each message until persistent continuation
  # is re-enabled against the current session-events contract.
  payload="$(jq -n --arg id "agent_ab723545fb484badafe97a5593ffcdd0954b67630a99464eba" --arg model "gpt-5.6-luna" --arg instructions "Официальный тон, пунктуальность, память, остроумие и критическое мышление." --arg input "$prompt" --arg sid "$session_id" 'if $sid == "" then {agent_id:$id,model:$model,instructions:$instructions,reasoning:{effort:"low",summary:"auto"},text:{format:{type:"text"},verbosity:"low"},environment:{type:"none"},input:$input,stream:true} else {events:[{type:"agent.session.input.message",input:[{role:"user",content:[{type:"input_text",text:$input}]}]}],stream:true} end')"
  stream_file="$(mktemp)"
  if [[ -n "$session_id" ]]; then
    curl --no-buffer -sS -X POST "$AGENTS/sessions/$session_id/events" -H "OpenAI-Beta: agents=v1" -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" -d "$payload" >"$stream_file" &
  else
    curl --no-buffer -sS -X POST "$AGENTS/sessions" -H "OpenAI-Beta: agents=v1" -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" -d "$payload" >"$stream_file" &
  fi
  curl_pid=$!
  for _ in {1..180}; do
    if grep -Eq 'agent.session.turn.(output_text.done|completed|failed|cancelled)' "$stream_file"; then
      kill "$curl_pid" 2>/dev/null || true
      break
    fi
    kill -0 "$curl_pid" 2>/dev/null || break
    sleep 1
  done
  wait "$curl_pid" 2>/dev/null || true
  session_id="$(sed -n 's/^data: //p' "$stream_file" | jq -r 'select(.type=="agent.session.created") | .session.id' | head -1)"
  [[ -n "$session_id" ]] && printf '%s' "$session_id" >"$STATE/$user_id"
  answer="$(sed -n 's/^data: //p' "$stream_file" | jq -r '.. | objects | (.text? // .value? // empty)' | tail -1)"
  if [[ -z "$answer" ]]; then
    printf 'Agents API returned no final text event:\n' >&2
    sed -n 's/^data: //p' "$stream_file" | tail -5 >&2 || true
  fi
  rm -f "$stream_file"
  [[ -n "$answer" ]] && printf '%s' "$answer" || printf '%s' "Не удалось получить ответ от Life Manager."
}

echo "Telegram bot is running. Press Ctrl-C to stop." >&2
while true; do
  updates="$(curl -sS "$TG/getUpdates" --get --data-urlencode "timeout=25" --data-urlencode "offset=$offset")" || continue
  while IFS= read -r update; do
    [[ -z "$update" ]] && continue
    update_id="$(jq -r '.update_id' <<<"$update")"
    (( offset = update_id + 1 ))
    chat_id="$(jq -r '.message.chat.id // empty' <<<"$update")"
    user_id="$(jq -r '.message.from.id // empty' <<<"$update")"
    message="$(jq -r '.message.text // empty' <<<"$update")"
    [[ -z "$chat_id" || -z "$message" ]] && continue
    if [[ "$message" == "/start" ]]; then
      send_message "$chat_id" "Здравствуйте. Я Life Manager. Напишите, что нужно организовать."
      continue
    fi
    answer="$(reply_from_agents "$user_id" "$message")" || answer="Произошла ошибка при обращении к Life Manager."
    send_message "$chat_id" "$answer"
  done < <(jq -c '.result[]?' <<<"$updates")
done
