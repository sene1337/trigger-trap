#!/usr/bin/env bash
# send-guard.sh — Block outbound questions to Brad unless a fresh gate artifact exists.
# Detects question-like text via '?', leading interrogatives, and veiled asks.
# On block: prints BLOCKED_BY_GUARD: run pre-ask gate (exit 1)
# On allow: prints ASK_ALLOWED (exit 0)
# Non-questions pass through silently (exit 0).
# Explicit 1-3-1 structured messages bypass gate even if question-like.
#
# Usage:
#   send-guard.sh [OPTIONS] "<message text>"
#
# Options:
#   -h, --help   Show this help
#
# Example:
#   send-guard.sh "How should I handle the Kazuo position?"
#   send-guard.sh "The report is ready."

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
WORKSPACE="${WORKSPACE:-/Users/senemaro/.openclaw/workspace}"
GATE_FILE="${WORKSPACE}/.gate/ask-allowed.json"
LOG_FILE="${WORKSPACE}/logs/ask-guard.log"
TTL_FALLBACK="${ASK_GATE_TOKEN_TTL_SECONDS:-600}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log_event() {
  local decision="$1" reason="$2"
  local ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  mkdir -p "$(dirname "${LOG_FILE}")"
  echo "${ts} | send-guard | ${decision} | ${reason}" >> "${LOG_FILE}"
}

usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,2\}//'
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  echo "ERROR: message text is required." >&2
  usage
fi

case "$1" in
  -h|--help) usage ;;
esac

MESSAGE="$1"

is_structured_131_bypass() {
  local text="$1"
  if echo "${text}" | grep -qiE '(^|[^0-9])1[[:space:]/-]*3[[:space:]/-]*1([^0-9]|$)'; then
    return 0
  fi

  if echo "${text}" | grep -qE '(^|[[:space:]])1[.)][[:space:]]' \
    && echo "${text}" | grep -qE '(^|[[:space:]])2[.)][[:space:]]' \
    && echo "${text}" | grep -qE '(^|[[:space:]])3[.)][[:space:]]'; then
    return 0
  fi

  return 1
}

is_status_only_bypass() {
  local text="$1"
  local found=0
  local line trimmed

  while IFS= read -r line || [[ -n "${line}" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "${trimmed}" ]] && continue
    found=1

    if [[ ! "${trimmed}" =~ ^([-*][[:space:]]*)?(DONE|BLOCKED)[[:space:]]*: ]] \
      && [[ ! "${trimmed}" =~ ^([-*][[:space:]]*)?HEARTBEAT_OK([[:space:]]|$) ]]; then
      return 1
    fi
  done <<< "${text}"

  [[ "${found}" -eq 1 ]]
}

# ── 1-3-1 and status bypasses (allowed without artifact) ─────────────────────
if is_structured_131_bypass "${MESSAGE}"; then
  log_event "ALLOW" "1-3-1 marker bypass | msg='${MESSAGE:0:80}'"
  echo "ASK_ALLOWED"
  exit 0
fi

if is_status_only_bypass "${MESSAGE}"; then
  log_event "ALLOW" "status/heartbeat bypass | msg='${MESSAGE:0:80}'"
  echo "ASK_ALLOWED"
  exit 0
fi

# ── Question detection ────────────────────────────────────────────────────────
INTERROGATIVES="^(who|what|when|where|why|how|which|can|could|should|would|do|did|does|is|are|am|will|have|has|had|may|might)[[:space:]]"
VEILED_ASKS="if you want|if you'd like|if you would like|let me know if"
VEILED_CAN="i can.{0,120}(if you want|if you'd like|if you would like)"

is_question=false
if [[ "${MESSAGE}" == *"?"* ]]; then
  is_question=true
elif echo "${MESSAGE}" | grep -qiE "${INTERROGATIVES}"; then
  is_question=true
elif echo "${MESSAGE}" | grep -qiE "${VEILED_ASKS}"; then
  is_question=true
elif echo "${MESSAGE}" | grep -qiE "${VEILED_CAN}"; then
  is_question=true
fi

if [[ "${is_question}" == false ]]; then
  log_event "PASS_THROUGH" "non-question text: '${MESSAGE:0:80}'"
  exit 0
fi

# ── Gate artifact check ───────────────────────────────────────────────────────
NOW=$(date +%s)

if [[ ! -f "${GATE_FILE}" ]]; then
  log_event "BLOCK" "no gate artifact | msg='${MESSAGE:0:80}'"
  echo "BLOCKED_BY_GUARD: run pre-ask gate"
  exit 1
fi

# Extract expiresAtEpoch from JSON (with legacy fallback for older artifacts)
EXPIRES_AT=$(python3 -c "
import json, sys
try:
    data = json.load(open('${GATE_FILE}'))
    created = data.get('createdAtEpoch', data.get('created_at', 0))
    expires = data.get('expiresAtEpoch', data.get('expires_at'))
    if expires is None and created:
        expires = int(created) + int('${TTL_FALLBACK}')
    print(int(expires or 0))
except Exception:
    print(0)
")

if [[ "${EXPIRES_AT}" -le "${NOW}" ]]; then
  log_event "BLOCK" "gate artifact expired (expiresAtEpoch=${EXPIRES_AT}, now=${NOW}) | msg='${MESSAGE:0:80}'"
  echo "BLOCKED_BY_GUARD: run pre-ask gate"
  exit 1
fi

# ── Valid gate — allow ────────────────────────────────────────────────────────
REMAINING=$(( EXPIRES_AT - NOW ))
log_event "ALLOW" "valid gate artifact (${REMAINING}s remaining) | msg='${MESSAGE:0:80}'"
echo "ASK_ALLOWED"
exit 0
